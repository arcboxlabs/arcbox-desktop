import SwiftUI

struct ContentView: View {
    var body: some View {
        MainContentView()
    }
}

#Preview {
    ContentView()
        .environment(AppViewModel())
}
