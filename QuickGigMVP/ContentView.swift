import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("preferredRole") private var preferredRoleRawValue = ""

    var body: some View {
        Group {
            if appState.isLoggedIn {
                MainMapView()
            } else if !hasSeenOnboarding {
                OnboardingView {
                    hasSeenOnboarding = true
                }
            } else if let preferredRole {
                LoginView(selectedRole: preferredRole) {
                    preferredRoleRawValue = ""
                }
            } else {
                RoleSelectionView { role in
                    preferredRoleRawValue = role.rawValue
                }
            }
        }
        .animation(.smooth, value: appState.isLoggedIn)
        .animation(.smooth, value: hasSeenOnboarding)
        .animation(.smooth, value: preferredRoleRawValue)
    }

    private var preferredRole: UserRole? {
        UserRole(rawValue: preferredRoleRawValue)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
