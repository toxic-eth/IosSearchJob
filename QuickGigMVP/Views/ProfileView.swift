import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("preferredRole") private var preferredRoleRawValue = ""
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.uk.rawValue

    @State private var selectedUserId: UUID?
    @State private var stars = 5
    @State private var comment = ""
    @State private var showSettings = false
    @State private var resumeText = ""

    private var language: AppLanguage { resolvedLanguage(from: appLanguageRawValue) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                if let currentUser = appState.currentUser {
                    ScrollView {
                        VStack(spacing: 12) {
                            userCard(currentUser)
                            settingsShortcut
                            resumeCard(currentUser)
                            reviewComposer(currentUser)
                            recentReviews(currentUser)
                            accountActions
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle(I18n.t("profile.title", language))
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                resumeText = appState.currentUser?.resumeSummary ?? ""
            }
            .onChange(of: appState.currentUser?.resumeSummary) { _, newValue in
                resumeText = newValue ?? ""
            }
        }
    }

    private func userCard(_ currentUser: AppUser) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.purple.opacity(0.28))
                .frame(width: 56, height: 56)
                .overlay {
                    Text(currentUser.initials)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(currentUser.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(currentUser.role.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Рейтинг: \(currentUser.rating, specifier: "%.1f") (\(currentUser.reviewsCount) відгуків)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard()
    }

    private func reviewComposer(_ currentUser: AppUser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Залишити відгук")
                .font(.headline)
                .foregroundStyle(.primary)

            Picker("Кому", selection: $selectedUserId) {
                Text(I18n.t("profile.review_for", language)).tag(UUID?.none)
                ForEach(appState.users.filter { $0.id != currentUser.id }) { user in
                    Text("\(user.name) • \(user.role.title)").tag(UUID?.some(user.id))
                }
            }
            .pickerStyle(.menu)

            Stepper("Зірки: \(stars)", value: $stars, in: 1...5)
                .foregroundStyle(.primary)

            TextField("Відгук", text: $comment)
                .textFieldStyle(.roundedBorder)

            Button(I18n.t("profile.send", language)) {
                guard let selectedUserId else { return }
                appState.addReview(to: selectedUserId, stars: stars, comment: comment)
                comment = ""
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(selectedUserId == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func recentReviews(_ currentUser: AppUser) -> some View {
        let mine = appState.reviews(for: currentUser.id)

        return VStack(alignment: .leading, spacing: 8) {
            Text(I18n.t("profile.reviews", language))
                .font(.headline)
                .foregroundStyle(.primary)

            if mine.isEmpty {
                Text(I18n.t("profile.review_empty", language))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(mine.prefix(8)) { review in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(repeating: "★", count: review.stars))
                            .foregroundStyle(.orange)
                        Text(review.comment.isEmpty ? "Без тексту" : review.comment)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text(review.date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var accountActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(I18n.t("profile.account", language))
                .font(.headline)
                .foregroundStyle(.primary)

            Button(I18n.t("profile.logout", language)) {
                appState.logout()
            }
            .buttonStyle(.bordered)
            .tint(.red)

            Button(I18n.t("profile.change_role", language)) {
                preferredRoleRawValue = ""
                appState.logout()
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var settingsShortcut: some View {
        HStack {
            Label(I18n.t("profile.settings", language), systemImage: "gearshape.fill")
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .onTapGesture {
            showSettings = true
        }
        .glassCard()
    }

    private func resumeCard(_ currentUser: AppUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(I18n.t("profile.resume", language))
                .font(.headline)
                .foregroundStyle(.primary)

            if currentUser.role == .worker {
                TextEditor(text: $resumeText)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Button(I18n.t("profile.resume_save", language)) {
                    appState.updateCurrentUserResume(resumeText)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            } else {
                Text(I18n.t("profile.resume_placeholder", language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
