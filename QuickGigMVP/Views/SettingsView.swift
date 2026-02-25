import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.dark.rawValue
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.uk.rawValue
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    @State private var securityEmail = ""
    @State private var securityCode = ""
    @State private var oldEmailForChange = ""
    @State private var newEmailForChange = ""

    private var language: AppLanguage { resolvedLanguage(from: appLanguageRawValue) }
    private var privacyPolicyURL: URL {
        configuredURL(for: "PrivacyPolicyURL", fallback: "http://127.0.0.1:8000/legal/privacy")
    }
    private var termsURL: URL {
        configuredURL(for: "TermsOfUseURL", fallback: "http://127.0.0.1:8000/legal/terms")
    }
    private var supportURL: URL {
        configuredURL(for: "SupportURL", fallback: "http://127.0.0.1:8000/legal/support")
    }
    private var supportEmail: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SupportEmail") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "support@quickgig.app" : trimmed
    }
    private var supportMailURL: URL {
        URL(string: "mailto:\(supportEmail)") ?? URL(string: "mailto:support@quickgig.app")!
    }

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

                        VStack(alignment: .leading, spacing: 12) {
                            Text(I18n.t("settings.legal", language))
                                .font(.headline)
                                .foregroundStyle(.primary)

                            legalLinkRow(
                                title: I18n.t("settings.privacy_policy", language),
                                url: privacyPolicyURL
                            )
                            legalLinkRow(
                                title: I18n.t("settings.terms_of_use", language),
                                url: termsURL
                            )
                            legalLinkRow(
                                title: I18n.t("settings.support_site", language),
                                url: supportURL
                            )

                            Link(destination: supportMailURL) {
                                HStack {
                                    Text(I18n.t("settings.support_email", language))
                                    Spacer()
                                    Text(supportEmail)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
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

    private func configuredURL(for key: String, fallback: String) -> URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let candidate = (raw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? raw!
            : fallback
        return URL(string: candidate) ?? URL(string: fallback)!
    }

    @ViewBuilder
    private func legalLinkRow(title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
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
                    oldEmailForChange = appState.currentUser?.email ?? ""
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
            } else if appState.emailVerificationStep == .enterChangeEmails {
                TextField("Стара пошта", text: $oldEmailForChange)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)

                TextField("Нова пошта", text: $newEmailForChange)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)

                Button("Запросити коди підтвердження") {
                    _ = appState.startEmailChange(oldEmail: oldEmailForChange, newEmail: newEmailForChange)
                    securityCode = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            } else if appState.emailVerificationStep == .verifyOldEmail {
                verificationCodeBlock(
                    title: "Введіть код зі старої пошти",
                    buttonTitle: "Підтвердити стару пошту",
                    demoCode: appState.emailVerificationDemoCode
                ) {
                    _ = appState.confirmOldEmailForChange(code: securityCode)
                }
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
