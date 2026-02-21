import SwiftUI

private enum AuthMode: String, CaseIterable, Identifiable {
    case login
    case register

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login:
            return "Вход"
        case .register:
            return "Регистрация"
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var appState: AppState

    @State private var mode: AuthMode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var selectedRole: UserRole = .worker

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.5), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QuickGig")
                                .font(.largeTitle.bold())
                            Text("Подработка на день или неделю. Откликайтесь, нанимайте, оценивайте.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        VStack(spacing: 16) {
                            Picker("Режим", selection: $mode) {
                                ForEach(AuthMode.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)

                            if mode == .register {
                                TextField("Имя или компания", text: $name)
                                    .textFieldStyle(.roundedBorder)
                            }

                            TextField("Email", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textFieldStyle(.roundedBorder)

                            SecureField("Пароль", text: $password)
                                .textFieldStyle(.roundedBorder)

                            if mode == .register {
                                SecureField("Повторите пароль", text: $confirmPassword)
                                    .textFieldStyle(.roundedBorder)

                                Picker("Роль", selection: $selectedRole) {
                                    ForEach(UserRole.allCases) { role in
                                        Text(role.title).tag(role)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            if let error = appState.authErrorMessage {
                                Text(error)
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button(actionTitle) {
                                submit()
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)

                            demoAccounts
                        }
                        .padding(20)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var actionTitle: String {
        mode == .login ? "Войти" : "Создать аккаунт"
    }

    private var demoAccounts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Демо: alex@quickgig.app / 123456")
            Text("Демо: cafe@quickgig.app / 123456")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() {
        if mode == .login {
            _ = appState.login(email: email, password: password)
            return
        }

        guard password == confirmPassword else {
            appState.authErrorMessage = "Пароли не совпадают"
            return
        }

        _ = appState.register(name: name, email: email, password: password, role: selectedRole)
    }
}
