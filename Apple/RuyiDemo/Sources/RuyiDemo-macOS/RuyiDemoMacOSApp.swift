import SwiftUI

@main
struct RuyiDemoMacOSApp: App {
    var body: some Scene {
        WindowGroup("RuyiDemo-macOS") {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        // Keep chrome minimal so the sidebar starts flush under the title bar.
        .windowToolbarStyle(.unifiedCompact)
    }
}
