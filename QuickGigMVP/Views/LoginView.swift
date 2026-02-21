import SwiftUI

private enum AuthMode: String, CaseIterable, Identifiable {
    case login
    case register

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login:
            return "Вхід"
        case .register:
            return "Реєстрація"
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var appState: AppState

    let selectedRole: UserRole
    let onResetRole: () -> Void

    @State private var mode: AuthMode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

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
                        header

                        VStack(spacing: 14) {
                            Picker("Режим", selection: $mode) {
                                ForEach(AuthMode.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)

                            if mode == .register {
                                TextField(namePlaceholder, text: $name)
                                    .textFieldStyle(.roundedBorder)
                            }

                            TextField(emailPlaceholder, text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled(true)
                                .textFieldStyle(.roundedBorder)

                            PasswordInputField(
                                title: "Пароль",
                                text: $password
                            )

                            if mode == .register {
                                PasswordInputField(
                                    title: "Повторіть пароль",
                                    text: $confirmPassword
                                )
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

                            Button(changeRoleTitle) {
                                onResetRole()
                            }
                            .font(.footnote)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedRole == .worker ? "Шукаю підробіток" : "Шукаю працівників")
                .font(.largeTitle.bold())
            Text(selectedRole == .worker
                 ? "Знаходьте зміни на мапі та відгукуйтесь за хвилину."
                 : "Публікуйте зміни та швидко знаходьте виконавців.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var actionTitle: String {
        mode == .login ? "Увійти" : "Створити акаунт"
    }

    private var namePlaceholder: String {
        selectedRole == .worker ? "Ім'я та прізвище" : "Назва компанії"
    }

    private var emailPlaceholder: String {
        selectedRole == .worker ? "Ваш email" : "Email компанії"
    }

    private var changeRoleTitle: String {
        selectedRole == .worker
            ? "Я роботодавець"
            : "Я шукаю підробіток"
    }

    private func submit() {
        if mode == .login {
            _ = appState.login(email: email, password: password, expectedRole: selectedRole)
            return
        }

        guard password == confirmPassword else {
            appState.authErrorMessage = "Паролі не збігаються"
            return
        }

        _ = appState.register(name: name, email: email, password: password, role: selectedRole)
    }
}

private struct PasswordInputField: View {
    let title: String
    @Binding var text: String

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isVisible {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .textContentType(.oneTimeCode)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
