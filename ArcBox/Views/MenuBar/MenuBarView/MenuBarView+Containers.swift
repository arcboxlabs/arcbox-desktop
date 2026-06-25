import SwiftUI

extension MenuBarView {
    // MARK: - Containers Section

    var containersSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            containersHeader

            if hasContainers {
                containerListViewport
            }
        }
    }

    var containerListViewport: some View {
        ZStack(alignment: .topLeading) {
            if containersExpanded {
                containerList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(height: containersExpanded ? containerListHeight : 0, alignment: .top)
        .clipped()
    }

    var containersHeader: some View {
        Button {
            guard hasContainers else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                containersExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cube")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.accent)
                    .frame(width: 16)

                Text("Containers")
                    .font(.system(size: 13, weight: .medium))

                Spacer(minLength: 0)

                Text("\(containersVM.runningCount) running")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(hasContainers ? 1 : 0.35)
                    .rotationEffect(.degrees(containersExpanded && hasContainers ? 90 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        containersExpanded && hasContainers
                            ? AnyShapeStyle(.quaternary.opacity(0.30))
                            : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasContainers)
    }

    var containerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: containerRowSpacing) {
                ForEach(displayedContainers) { container in
                    containerRow(container)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: containerListHeight)
        .padding(.leading, 12)
    }

    func containerRow(_ container: ContainerViewModel) -> some View {
        MenuBarHoverButton {
            containersVM.selectContainer(container.id)
            appVM.navigate(to: .containers)
            showArcBoxWindow()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(container.state.color)
                    .frame(width: 7, height: 7)

                Text(container.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(container.state.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(height: containerRowHeight)
        }
    }

}
