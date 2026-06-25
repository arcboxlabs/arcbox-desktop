import AppKit

extension LocalRootFSOutlineCoordinator {
    func loadRootNodes() {
        generation += 1
        let currentGeneration = generation
        let rootURL = parent.rootURL
        let showHidden = parent.showHiddenFiles

        rootNodes = []
        outlineView?.reloadData()
        parent.selectedPath = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let entries: [LocalFileEntry]
            do {
                entries = try FileSystemService.listDirectory(at: rootURL, showHiddenFiles: showHidden)
            } catch {
                entries = []
            }

            DispatchQueue.main.async {
                guard currentGeneration == self.generation else { return }
                self.rootNodes = entries.map { LocalFileNode(entry: $0, parent: nil) }
                self.outlineView?.reloadData()
                self.adjustColumnWidths(force: true)
                DispatchQueue.main.async {
                    self.adjustColumnWidths(force: true)
                }
            }
        }
    }

    func loadChildrenIfNeeded(for node: LocalFileNode) {
        guard node.entry.isExpandable, node.children == nil, !node.isLoading else { return }

        node.isLoading = true
        let currentGeneration = generation
        let showHidden = parent.showHiddenFiles

        DispatchQueue.global(qos: .userInitiated).async {
            let children: [LocalFileEntry]
            do {
                children = try FileSystemService.listDirectory(at: node.entry.url, showHiddenFiles: showHidden)
            } catch {
                children = []
            }

            DispatchQueue.main.async {
                guard currentGeneration == self.generation else { return }
                node.isLoading = false
                node.children = children.map { LocalFileNode(entry: $0, parent: node) }
                self.outlineView?.reloadItem(node, reloadChildren: true)
                self.adjustColumnWidths()
                DispatchQueue.main.async {
                    self.adjustColumnWidths()
                }
            }
        }
    }

}
