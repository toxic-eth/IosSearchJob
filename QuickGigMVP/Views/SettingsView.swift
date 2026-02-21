import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.uk.rawValue
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    @State private var securityEmail = ""
    @State private var securityCode = ""
    @State private var newEmailForChange = ""

    private var language: AppLanguage { resolvedLanguage(from: appLanguageRawValue) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                ScrollView {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(I18n.t("settings.appearance", language))
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Picker(I18n.t("settings.theme", language), selection: $appThemeRawValue) {
                                Text(I18n.t("theme.dark", language)).tag(AppTheme.dark.rawValue)
                                Text(I18n.t("theme.light", language)).tag(AppTheme.light.rawValue)
                            }
                            .pickerStyle(.segmented)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()

                        VStack(alignment: .leading, spacing: 10) {
                            Text(I18n.t("settings.language", language))
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Picker(I18n.t("settings.language", language), selection: $appLanguageRawValue) {
                                ForEach(AppLanguage.allCases) { item in
                                    Text(item.title).tag(item.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()

                        VStack(alignment: .leading, spacing: 10) {
                            Text(I18n.t("settings.notifications", language))
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Toggle(I18n.t("settings.local_notifications", language), isOn: $notificationsEnabled)
                                .tint(.purple)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()

                        VStack(alignment: .leading, spacing: 10) {
                            Text(I18n.t("settings.security", language))
                                .font(.headline)
                                .foregroundStyle(.primary)

                            securitySection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(I18n.t("settings.title", language))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(I18n.t("settings.done", language)) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                securityEmail = appState.currentUser?.email ?? ""
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        if let currentUser = appState.currentUser, currentUser.isEmailVerified, appState.emailVerificationStep == .none {
            Text(currentUser.email)
                .foregroundStyle(.primary)
                .font(.subheadline)

            HStack {
                Spacer()
                Button {
                    securityCode = ""
                    newEmailForChange = ""
                    appState.beginEmailChange()
                } label: {
                    Text("Змінити пошту")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        } else {
            if appState.emailVerificationStep == .none {
                TextField(I18n.t("settings.security.email", language), text: $securityEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)

                Button(I18n.t("settings.security.save_email", language)) {
                    _ = appState.startFirstEmailVerification(email: securityEmail)
                    securityCode = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            } else if appState.emailVerificationStep == .confirmFirstEmail {
                verificationCodeBlock(
                    title: "Підтвердіть email кодом",
                    buttonTitle: "Підтвердити email",
                    demoCode: appState.emailVerificationDemoCode
                ) {
                    _ = appState.confirmFirstEmail(code: securityCode)
                }
            } else if appState.emailVerificationStep == .verifyOldEmail {
                verificationCodeBlock(
                    title: "Введіть код зі старої пошти",
                    buttonTitle: "Підтвердити стару пошту",
                    demoCode: appState.emailVerificationDemoCode
                ) {
                    _ = appState.confirmOldEmailForChange(code: securityCode)
                }
            } else if appState.emailVerificationStep == .enterNewEmail {
                TextField("Нова пошта", text: $newEmailForChange)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)

                Button("Надіслати код на нову пошту") {
                    _ = appState.submitNewEmailForChange(newEmailForChange)
                    securityCode = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            } else if appState.emailVerificationStep == .verifyNewEmail {
                verificationCodeBlock(
                    title: "Введіть код з нової пошти",
                    buttonTitle: "Підтвердити нову пошту",
                    demoCode: appState.emailVerificationDemoCode
                ) {
                    _ = appState.confirmNewEmailForChange(code: securityCode)
                }
            }

            if let error = appState.authErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func verificationCodeBlock(title: String, buttonTitle: String, demoCode: String, onSubmit: @escaping () -> Void) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondary)

        TextField("Код підтвердження", text: $securityCode)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)

        if !demoCode.isEmpty {
            Text("Демо-код: \(demoCode)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        Button(buttonTitle) {
            onSubmit()
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
    }
}
