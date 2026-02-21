import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isLoggedIn {
                MainMapView()
            } else {
                LoginView()
            }
        }
        .animation(.smooth, value: appState.isLoggedIn)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
