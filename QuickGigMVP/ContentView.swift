import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    @AppStorage("preferredRole") private var preferredRoleRawValue = ""
    @State private var showOnboarding = true

    var body: some View {
        Group {
            if appState.isLoggedIn {
                if appState.requiresPhoneVerification {
                    PhoneVerificationView()
                } else {
                    MainMapView()
                }
            } else if showOnboarding {
                OnboardingView(
                    onSkip: {
                        showOnboarding = false
                    },
                    onSelectRole: { role in
                        preferredRoleRawValue = role.rawValue
                        showOnboarding = false
                    }
                )
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
        .animation(.smooth, value: showOnboarding)
        .animation(.smooth, value: preferredRoleRawValue)
        .onChange(of: appState.isLoggedIn) { _, isLoggedIn in
            if !isLoggedIn {
                showOnboarding = true
            }
        }
    }

    private var preferredRole: UserRole? {
        UserRole(rawValue: preferredRoleRawValue)
    }
}
