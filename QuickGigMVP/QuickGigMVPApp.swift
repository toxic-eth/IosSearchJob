import SwiftUI

@main
struct QuickGigMVPApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var locationService = LocationService()
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue

    var body: some Scene {
        let theme = resolvedTheme(from: appThemeRawValue)

        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(locationService)
                .preferredColorScheme(theme.colorScheme)
        }
    }
}
