import SwiftUI

struct AboutView: View {
    @State var releases: [ChangelogRelease] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                versionInfoSection
                whatsNewSection
                helpSection
                footerSection
            }
            .padding(24)
        }
        .task {
            let loadedReleases = await Task.detached(priority: .utility) {
                ChangelogParser.loadFromBundle(limit: 3)
            }.value

            await MainActor.run {
                releases = loadedReleases
            }
        }
    }
}

#Preview {
    AboutView()
        .frame(width: 500, height: 660)
}
