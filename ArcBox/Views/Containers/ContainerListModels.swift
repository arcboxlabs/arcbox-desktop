import AppKit

@MainActor
final class ContainersOutlineView: NSOutlineView {
    #if DEBUG
        /// Structural updates issued so far; tests read these to pin that a snapshot
        /// change produced exactly the row operations it should have.
        struct UpdateCounts: Equatable {
            var reloads = 0
            var inserts = 0
            var removes = 0
            var moves = 0
        }

        private(set) var updateCounts = UpdateCounts()

        override func reloadData() {
            updateCounts.reloads += 1
            super.reloadData()
        }

        override func insertItems(
            at indexes: IndexSet,
            inParent parent: Any?,
            withAnimation animationOptions: NSTableView.AnimationOptions = []
        ) {
            updateCounts.inserts += indexes.count
            super.insertItems(at: indexes, inParent: parent, withAnimation: animationOptions)
        }

        override func removeItems(
            at indexes: IndexSet,
            inParent parent: Any?,
            withAnimation animationOptions: NSTableView.AnimationOptions = []
        ) {
            updateCounts.removes += indexes.count
            super.removeItems(at: indexes, inParent: parent, withAnimation: animationOptions)
        }

        override func moveItem(
            at fromIndex: Int,
            inParent oldParent: Any?,
            to toIndex: Int,
            inParent newParent: Any?
        ) {
            updateCounts.moves += 1
            super.moveItem(at: fromIndex, inParent: oldParent, to: toIndex, inParent: newParent)
        }
    #endif

    override func frameOfOutlineCell(atRow _: Int) -> NSRect {
        .zero
    }
}

struct ContainerListPresentation: Equatable {
    let container: ContainerViewModel

    static func == (
        lhs: ContainerListPresentation,
        rhs: ContainerListPresentation
    ) -> Bool {
        lhs.container.id == rhs.container.id
            && lhs.container.name == rhs.container.name
            && lhs.container.image == rhs.container.image
            && lhs.container.state == rhs.container.state
            && lhs.container.isTransitioning == rhs.container.isTransitioning
            && lhs.container.ports == rhs.container.ports
            && lhs.container.composeProject == rhs.container.composeProject
            && lhs.container.composeService == rhs.container.composeService
            && lhs.container.iconURL == rhs.container.iconURL
    }
}

enum ContainerListNodePresentation: Equatable {
    case section(String)
    case compose(project: String, containers: [ContainerListPresentation])
    case container(ContainerListPresentation)

    var id: ContainerListNodeID {
        switch self {
        case .section(let title):
            .section(title)
        case .compose(let project, _):
            .compose(project)
        case .container(let container):
            .container(container.container.id)
        }
    }

    /// The presentations of this node's children, in display order.
    var childPresentations: [ContainerListNodePresentation] {
        guard case .compose(_, let containers) = self else { return [] }
        return containers.map(ContainerListNodePresentation.container)
    }
}

/// The view-model state the outline renders, flattened into root presentations.
@MainActor
struct ContainerListSnapshot: Equatable {
    let loadState: LoadPhase
    let hasContainers: Bool
    let roots: [ContainerListNodePresentation]
    let expandedGroups: Set<String>
    let searchText: String
    let selectedID: String?

    init(viewModel: ContainersViewModel) {
        loadState = viewModel.loadState
        hasContainers = !viewModel.containers.isEmpty
        expandedGroups = viewModel.expandedGroups
        searchText = viewModel.searchText
        selectedID = viewModel.selectedID

        let groups = viewModel.composeGroups.map {
            (
                project: $0.project,
                containers: $0.containers.map(ContainerListPresentation.init)
            )
        }
        let activeGroups = groups.filter {
            $0.containers.contains { $0.container.isRunning }
        }
        let stoppedGroups = groups.filter {
            !$0.containers.contains { $0.container.isRunning }
        }
        let standalone = viewModel.standaloneContainers.map(
            ContainerListPresentation.init
        )
        let runningStandalone = standalone.filter(\.container.isRunning)
        let stoppedStandalone = standalone.filter { !$0.container.isRunning }

        var roots: [ContainerListNodePresentation] = []
        if !activeGroups.isEmpty || !runningStandalone.isEmpty {
            roots.append(.section("In Use"))
            roots.append(
                contentsOf: activeGroups.map {
                    .compose(project: $0.project, containers: $0.containers)
                })
            roots.append(contentsOf: runningStandalone.map(ContainerListNodePresentation.container))
        }
        if !stoppedGroups.isEmpty || !stoppedStandalone.isEmpty {
            roots.append(.section("Stopped"))
            roots.append(
                contentsOf: stoppedGroups.map {
                    .compose(project: $0.project, containers: $0.containers)
                })
            roots.append(contentsOf: stoppedStandalone.map(ContainerListNodePresentation.container))
        }
        self.roots = roots
    }
}

enum ContainerListNodeID: Hashable {
    case section(String)
    case compose(String)
    case container(String)
}

/// One row of the container outline.
///
/// `NSOutlineView` tracks rows, expansion, and selection by item identity, so a
/// node lives as long as its `id` stays in the tree and only its
/// `presentation` changes underneath it. `ContainerListTree` is the sole
/// mutator; nodes are inert outside it.
final class ContainerListNode: NSObject {
    let id: ContainerListNodeID
    fileprivate(set) var presentation: ContainerListNodePresentation
    fileprivate(set) var children: [ContainerListNode]

    init(_ presentation: ContainerListNodePresentation) {
        id = presentation.id
        self.presentation = presentation
        children = presentation.childPresentations.map(ContainerListNode.init)
    }
}

/// The outline's item tree plus the ordered edit script that turns one
/// snapshot into the next.
///
/// Steps are sequential: each one's indexes refer to the tree as it stands
/// after the steps before it, which is also how `NSOutlineView` interprets
/// `insertItems`/`removeItems`/`moveItem` inside `beginUpdates`/`endUpdates`.
/// `update(to:)` applies every step to the tree as it emits it, so replaying
/// the script on the outline view in order keeps data source and view in
/// lockstep at every call.
@MainActor
final class ContainerListTree {
    enum Step: Equatable {
        case remove(parent: ContainerListNode?, index: Int)
        case insert(parent: ContainerListNode?, index: Int, node: ContainerListNode)
        case move(parent: ContainerListNode?, from: Int, to: Int)
    }

    struct Update {
        var steps: [Step] = []
        /// Nodes whose presentation changed while their position did not; their
        /// visible cells need a `configure`, nothing else.
        var reconfigured: [ContainerListNode] = []
        /// Compose groups that entered or moved within the tree; the outline
        /// view re-applies the expansion state to these and no others.
        var repositionedGroups: [ContainerListNode] = []
    }

    private(set) var roots: [ContainerListNode] = []

    var isEmpty: Bool { roots.isEmpty }

    /// Replaces the whole tree with fresh nodes. Pair with `reloadData()`.
    func replace(with presentations: [ContainerListNodePresentation]) {
        roots = presentations.map(ContainerListNode.init)
    }

    /// Diffs the tree against `presentations` and returns the edit script that
    /// was applied.
    func update(to presentations: [ContainerListNodePresentation]) -> Update {
        var update = Update()
        Self.diffLevel(parent: nil, current: &roots, target: presentations, into: &update)
        for root in roots where root.presentation.childPresentations != root.children.map(\.presentation) {
            Self.diffLevel(
                parent: root,
                current: &root.children,
                target: root.presentation.childPresentations,
                into: &update
            )
        }
        return update
    }

    func node(for id: ContainerListNodeID) -> ContainerListNode? {
        for root in roots {
            if root.id == id {
                return root
            }
            if let child = root.children.first(where: { $0.id == id }) {
                return child
            }
        }
        return nil
    }

    private static func diffLevel(
        parent: ContainerListNode?,
        current: inout [ContainerListNode],
        target: [ContainerListNodePresentation],
        into update: inout Update
    ) {
        let targetIndexByID = Dictionary(
            target.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for index in current.indices.reversed() where targetIndexByID[current[index].id] == nil {
            current.remove(at: index)
            update.steps.append(.remove(parent: parent, index: index))
        }

        let survivingIDs = Set(current.map(\.id))
        let survivors = target.filter { survivingIDs.contains($0.id) }
        reorder(parent: parent, current: &current, survivors: survivors, into: &update)

        for (node, presentation) in zip(current, survivors) where node.presentation != presentation {
            node.presentation = presentation
            update.reconfigured.append(node)
        }

        for (index, presentation) in target.enumerated() where !survivingIDs.contains(presentation.id) {
            let node = ContainerListNode(presentation)
            current.insert(node, at: index)
            update.steps.append(.insert(parent: parent, index: index, node: node))
            if case .compose = presentation {
                update.repositionedGroups.append(node)
            }
        }
    }

    /// Moves the fewest nodes that put `current` into `survivors` order: the
    /// nodes already in relative order (a longest increasing subsequence of
    /// their target positions) stay put and every other node is moved in
    /// behind its target predecessor.
    private static func reorder(
        parent: ContainerListNode?,
        current: inout [ContainerListNode],
        survivors: [ContainerListNodePresentation],
        into update: inout Update
    ) {
        let targetIndexByID = Dictionary(
            survivors.enumerated().map { ($1.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let positions = current.map { targetIndexByID[$0.id]! }
        var placed = Set(longestIncreasingSubsequence(positions).map { current[$0].id })
        guard placed.count < current.count else { return }

        for (targetIndex, presentation) in survivors.enumerated() where !placed.contains(presentation.id) {
            let from = current.firstIndex { $0.id == presentation.id }!
            let node = current.remove(at: from)
            let predecessor = survivors[..<targetIndex].last { placed.contains($0.id) }
            let to =
                predecessor.map { predecessor in
                    current.firstIndex { $0.id == predecessor.id }! + 1
                } ?? 0
            current.insert(node, at: to)
            placed.insert(node.id)
            if from != to {
                update.steps.append(.move(parent: parent, from: from, to: to))
                if case .compose = presentation {
                    update.repositionedGroups.append(node)
                }
            }
        }
    }

    /// Indexes into `values` of one longest strictly increasing subsequence.
    private static func longestIncreasingSubsequence(_ values: [Int]) -> [Int] {
        guard !values.isEmpty else { return [] }
        var lengths = [Int](repeating: 1, count: values.count)
        var predecessors = [Int?](repeating: nil, count: values.count)
        for index in values.indices {
            for earlier in 0..<index where values[earlier] < values[index] && lengths[earlier] + 1 > lengths[index] {
                lengths[index] = lengths[earlier] + 1
                predecessors[index] = earlier
            }
        }
        var cursor: Int? = lengths.indices.max { lengths[$0] < lengths[$1] }
        var subsequence: [Int] = []
        while let index = cursor {
            subsequence.append(index)
            cursor = predecessors[index]
        }
        return subsequence.reversed()
    }
}
