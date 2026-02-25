import SwiftUI
import AuthenticationServices

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
    @State private var phone = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.purple.opacity(0.9), Color.indigo.opacity(0.6), Color.white],
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

                            TextField(phonePlaceholder, text: $phone)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.phonePad)
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

                            Button {
                                Task {
                                    await submit()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if appState.isAuthInFlight {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(actionTitle)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(appState.isAuthInFlight)

                            HStack(spacing: 10) {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(height: 1)
                                Text("або")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.25))
                                    .frame(height: 1)
                            }
                            .padding(.vertical, 2)

                            SignInWithAppleButton(
                                onRequest: { _ in },
                                onCompletion: { _ in
                                    _ = appState.loginWithApple(expectedRole: selectedRole)
                                }
                            )
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Button {
                                _ = appState.loginWithGoogle(expectedRole: selectedRole)
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 28, height: 28)
                                        Text("G")
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [Color.blue, Color.red, Color.yellow, Color.green],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                    Text("Продовжити з Google")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(Color.black.opacity(0.92))
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.black.opacity(0.14), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

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

    private var phonePlaceholder: String {
        selectedRole == .worker ? "Ваш номер телефону" : "Телефон компанії"
    }

    private var changeRoleTitle: String {
        selectedRole == .worker
            ? "Я роботодавець"
            : "Я шукаю підробіток"
    }

    @MainActor
    private func submit() async {
        if mode == .login {
            let success = await appState.loginWithBackend(phone: phone, password: password, expectedRole: selectedRole)
            if !success {
                _ = appState.login(phone: phone, password: password, expectedRole: selectedRole)
            }
            return
        }

        guard password == confirmPassword else {
            appState.authErrorMessage = "Паролі не збігаються"
            return
        }

        let success = await appState.registerWithBackend(name: name, phone: phone, password: password, role: selectedRole)
        if !success {
            _ = appState.register(name: name, phone: phone, password: password, role: selectedRole)
        }
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
