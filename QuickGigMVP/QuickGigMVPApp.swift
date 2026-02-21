import SwiftUI

@main
struct QuickGigMVPApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var locationService = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(locationService)
        }
    }
}
