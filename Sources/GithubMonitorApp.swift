import SwiftUI

@main
struct GithubMonitorApp: App {
    @State private var store = PullRequestStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
                .frame(width: 420, height: 500)
                .task {
                    await store.restoreSessionIfNeeded()
                }
        } label: {
            Label("GitHub Monitor", systemImage: "arrow.triangle.pull")
        }
        .menuBarExtraStyle(.window)
    }
}
