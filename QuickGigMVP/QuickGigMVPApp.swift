import SwiftUI
#if canImport(MapboxMaps)
import MapboxMaps
#endif

@main
struct QuickGigMVPApp: App {
    private static let mapboxPublicTokenFallback = "$(MAPBOX_ACCESS_TOKEN)"

    @StateObject private var appState = AppState()
    @StateObject private var locationService = LocationService()
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue

    init() {
        #if canImport(MapboxMaps)
        if let token = mapboxToken() {
            MapboxOptions.accessToken = token
        }
        #endif
    }

    var body: some Scene {
        let theme = resolvedTheme(from: appThemeRawValue)

        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(locationService)
                .preferredColorScheme(theme.colorScheme)
        }
    }

    private func mapboxToken() -> String? {
        let info = Bundle.main.infoDictionary
        let mbx = info?["MBXAccessToken"] as? String
        let mgl = info?["MGLMapboxAccessToken"] as? String
        let fromPlist = (mbx?.isEmpty == false ? mbx : mgl)
        let token = (fromPlist?.isEmpty == false ? fromPlist : Self.mapboxPublicTokenFallback)
        return token?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
