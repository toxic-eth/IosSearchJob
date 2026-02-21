import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState

    @State private var name = ""
    @State private var selectedRole: UserRole = .worker

    var body: some View {
        NavigationStack {
            Form {
                Section("Личный кабинет") {
                    TextField("Имя или название", text: $name)
                    Picker("Роль", selection: $selectedRole) {
                        ForEach(UserRole.allCases) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Button("Войти") {
                    appState.login(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "User" : name, role: selectedRole)
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("QuickGig MVP")
        }
    }
}
