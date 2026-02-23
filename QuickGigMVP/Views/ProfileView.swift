import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("preferredRole") private var preferredRoleRawValue = ""
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.uk.rawValue

    @State private var showSettings = false
    @State private var resumeText = ""
    @State private var selectedGuaranteeShift: JobShift?

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
                            payoutGuaranteeCard(currentUser)
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
            .sheet(item: $selectedGuaranteeShift) { shift in
                ShiftDetailView(shift: shift)
                    .environmentObject(appState)
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

    private func payoutGuaranteeCard(_ currentUser: AppUser) -> some View {
        guard currentUser.role == .worker else {
            return AnyView(EmptyView())
        }

        let acceptedApps = appState.applicationsForCurrentWorker()
            .filter { $0.status == .accepted }
        let paidCount = acceptedApps.filter { $0.progressStatus == .paid }.count
        let awaitingCount = acceptedApps.filter { $0.progressStatus == .completed }.count
        let inProgressCount = acceptedApps.filter { $0.progressStatus == .inProgress }.count

        let recentItems: [WorkerPayoutItem] = acceptedApps
            .compactMap { app in
                guard let shift = appState.shift(by: app.shiftId) else { return nil }
                return WorkerPayoutItem(application: app, shift: shift)
            }
            .sorted { lhs, rhs in
                if lhs.application.progressStatus == rhs.application.progressStatus {
                    return lhs.shift.endDate > rhs.shift.endDate
                }
                return payoutPriority(lhs.application.progressStatus) < payoutPriority(rhs.application.progressStatus)
            }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("Гарантія виплати")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    guaranteeStat(
                        title: "Оплачено",
                        value: paidCount,
                        color: .green
                    )
                    guaranteeStat(
                        title: "Очікує оплату",
                        value: awaitingCount,
                        color: .purple
                    )
                    guaranteeStat(
                        title: "В роботі",
                        value: inProgressCount,
                        color: .orange
                    )
                }

                if recentItems.isEmpty {
                    Text("Після прийнятої зміни тут з'явиться статус гарантії виплати")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentItems.prefix(6)) { item in
                        Button {
                            selectedGuaranteeShift = item.shift
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.shift.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    ProfileProgressBadge(status: item.application.progressStatus)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.shift.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(appState.guaranteeStateText(for: item.application))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        )
    }

    private func guaranteeStat(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func payoutPriority(_ status: WorkProgressStatus) -> Int {
        switch status {
        case .completed:
            return 0
        case .inProgress:
            return 1
        case .scheduled:
            return 2
        case .paid:
            return 3
        }
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

private struct WorkerPayoutItem: Identifiable {
    let application: ShiftApplication
    let shift: JobShift
    var id: UUID { application.id }
}

private struct ProfileProgressBadge: View {
    let status: WorkProgressStatus

    var body: some View {
        Text(status.title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundStyle(textColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .scheduled:
            return .blue.opacity(0.2)
        case .inProgress:
            return .orange.opacity(0.2)
        case .completed:
            return .purple.opacity(0.2)
        case .paid:
            return .green.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch status {
        case .scheduled:
            return .blue
        case .inProgress:
            return .orange
        case .completed:
            return .purple
        case .paid:
            return .green
        }
    }
}
