import SwiftUI

extension MenuBarView {
    // MARK: - Data

    func loadAll() async {
        async let c: () = containersVM.loadContainersFromDocker(docker: docker, iconClient: client)
        async let i: () = imagesVM.loadImages(docker: docker, iconClient: client)
        async let n: () = networksVM.loadNetworks(docker: docker)
        async let v: () = volumesVM.loadVolumes(docker: docker)
        _ = await (c, i, n, v)
    }

    // MARK: - Main Panel

    var mainPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
                .padding(.bottom, 4)

            metricCards

            containersSection

            Divider()
                .padding(.vertical, 2)

            actionSection
        }
        .frame(width: 260)
    }

    // MARK: - Header

    var header: some View {
        HStack(spacing: 12) {
            Text("ArcBox")
                .font(.headline)

            Spacer(minLength: 0)

            statusPill(title: daemonStateDisplay, color: daemonStateColor)
        }
        .padding(.leading, 4)
        .padding(.horizontal, 2)
    }

}
