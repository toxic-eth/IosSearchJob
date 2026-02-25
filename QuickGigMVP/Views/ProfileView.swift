import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @AppStorage("preferredRole") private var preferredRoleRawValue = ""
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.uk.rawValue

    @State private var showSettings = false
    @State private var resumeText = ""
    @State private var selectedGuaranteeShift: JobShift?
    @State private var companyNameDraft = ""
    @State private var taxIdDraft = ""
    @State private var riskAppealDraft = ""
    @State private var moderationNoteByCaseId: [UUID: String] = [:]
    @State private var selectedAuditTypeRaw = "all"
    @State private var selectedAuditWindowDays = 7

    private var language: AppLanguage { resolvedLanguage(from: appLanguageRawValue) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                if let currentUser = appState.currentUser {
                    ScrollView {
                        VStack(spacing: 12) {
                            if let error = appState.authErrorMessage, !error.isEmpty {
                                AppStateBanner(
                                    title: "Потрібна увага",
                                    message: error,
                                    tone: .warning,
                                    actionTitle: "Зрозуміло",
                                    action: { appState.authErrorMessage = nil }
                                )
                            }
                            userCard(currentUser)
                            trustCard(currentUser)
                            employerKycCard(currentUser)
                            riskAppealCard(currentUser)
                            moderatorQueueCard(currentUser)
                            auditTrailCard(currentUser)
                            employerWalletCard(currentUser)
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
                    .environmentObject(locationService)
            }
            .onAppear {
                resumeText = appState.currentUser?.resumeSummary ?? ""
                companyNameDraft = appState.currentUser?.employerCompanyName ?? ""
                taxIdDraft = appState.currentUser?.employerTaxId ?? ""
            }
            .onChange(of: appState.currentUser?.resumeSummary) { _, newValue in
                resumeText = newValue ?? ""
            }
            .onChange(of: appState.currentUser?.employerCompanyName) { _, newValue in
                companyNameDraft = newValue ?? ""
            }
            .onChange(of: appState.currentUser?.employerTaxId) { _, newValue in
                taxIdDraft = newValue ?? ""
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
                Text("Надійність: \(Int(currentUser.reliabilityScore))%")
                    .font(.caption2.bold())
                    .foregroundStyle(.purple)
            }
            Spacer()
        }
        .glassCard()
    }

    private func trustCard(_ currentUser: AppUser) -> some View {
        let risk = appState.riskScore(for: currentUser.id)
        let riskLevel = appState.riskLevel(for: currentUser.id)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                trustMetric(title: "Надійність", value: "\(Int(currentUser.reliabilityScore))%", tint: .purple)
                trustMetric(title: "Completion", value: percentage(currentUser.completionRate), tint: .green)
                trustMetric(title: "Cancel", value: percentage(currentUser.cancelRate), tint: .orange)
                trustMetric(title: "No-show", value: percentage(currentUser.noShowRate), tint: .red)
                trustMetric(title: "Risk", value: "\(Int(risk))% \(riskLevel.title)", tint: riskTint(riskLevel))
            }
        }
        .glassCard()
    }

    private func trustMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 118, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func riskTint(_ level: RiskLevel) -> Color {
        switch level {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
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

    @ViewBuilder
    private func employerKycCard(_ currentUser: AppUser) -> some View {
        if currentUser.role == .employer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Верифікація роботодавця")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    AppStatusPill(
                        title: currentUser.employerKYCStatus.title,
                        tone: kycStatusTone(currentUser.employerKYCStatus)
                    )
                }

                kycStatusBanner(for: currentUser.employerKYCStatus, note: currentUser.kycReviewNote)

                TextField("Назва компанії", text: $companyNameDraft)
                    .textFieldStyle(.roundedBorder)
                TextField("Tax ID", text: $taxIdDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button("Надіслати KYC") {
                        _ = appState.submitEmployerKYC(companyName: companyNameDraft, taxId: taxIdDraft)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func kycStatusColor(_ status: EmployerKYCStatus) -> Color {
        switch status {
        case .notSubmitted:
            return .secondary
        case .pending:
            return .orange
        case .verified:
            return .green
        case .rejected:
            return .red
        }
    }

    private func kycStatusTone(_ status: EmployerKYCStatus) -> AppPillTone {
        switch status {
        case .notSubmitted:
            return .neutral
        case .pending:
            return .warning
        case .verified:
            return .success
        case .rejected:
            return .danger
        }
    }

    @ViewBuilder
    private func kycStatusBanner(for status: EmployerKYCStatus, note: String) -> some View {
        switch status {
        case .verified:
            AppStateBanner(
                title: "KYC підтверджено",
                message: note.isEmpty ? "Акаунт роботодавця верифікований." : note,
                tone: .success
            )
        case .pending:
            AppStateBanner(
                title: "KYC на розгляді",
                message: "Модерація перевіряє документи. Це може зайняти кілька годин.",
                tone: .warning
            )
        case .rejected:
            AppStateBanner(
                title: "KYC відхилено",
                message: note.isEmpty ? "Перевірте дані компанії та подайте заявку повторно." : note,
                tone: .danger
            )
        case .notSubmitted:
            AppStateBanner(
                title: "KYC не подано",
                message: "Подайте верифікацію, щоб підвищити довіру та доступ до інструментів модерації.",
                tone: .neutral
            )
        }
    }

    private func riskAppealCard(_ currentUser: AppUser) -> some View {
        let risk = appState.riskScore(for: currentUser.id)
        let riskLevel = appState.riskLevel(for: currentUser.id)
        let cases = appState
            .moderationCasesForCurrentUser()
            .filter { $0.type == .riskAppeal }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Підтримка та апеляції")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack {
                Text("Поточний risk score: \(Int(risk))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                AppStatusPill(title: riskLevel.title, tone: riskTone(riskLevel))
            }

            if riskLevel == .high {
                AppStateBanner(
                    title: "Високий ризик",
                    message: "Можуть діяти обмеження на відгуки/дії. Подайте апеляцію для перегляду.",
                    tone: .danger
                )
            }

            TextField("Опишіть апеляцію по risk-обмеженню", text: $riskAppealDraft, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button("Подати апеляцію") {
                    _ = appState.submitRiskAppeal(reason: riskAppealDraft)
                    riskAppealDraft = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }

            ForEach(cases.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        AppStatusPill(title: item.status.title, tone: moderationStatusTone(item.status))
                        Text(item.details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !item.resolutionNote.isEmpty {
                        Text(item.resolutionNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private func moderatorQueueCard(_ currentUser: AppUser) -> some View {
        if appState.currentUserCanAccessModeration() {
            let queue = appState.moderationQueueOpenCases()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Модерація")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(queue.count)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                if queue.isEmpty {
                    Text("Відкритих кейсів немає")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(queue.prefix(6)) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(item.type.title) • \(item.subject)")
                                .font(.caption.bold())
                            Text(item.details)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            AppStatusPill(title: item.status.title, tone: moderationStatusTone(item.status))

                            TextField(
                                "Коментар модератора",
                                text: Binding(
                                    get: { moderationNoteByCaseId[item.id] ?? "" },
                                    set: { moderationNoteByCaseId[item.id] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            HStack(spacing: 8) {
                                Button("Схвалити") {
                                    let note = moderationNoteByCaseId[item.id] ?? "Кейс схвалено"
                                    _ = appState.processModerationCase(caseId: item.id, approve: true, note: note)
                                    moderationNoteByCaseId[item.id] = ""
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)

                                Button("Відхилити") {
                                    let note = moderationNoteByCaseId[item.id] ?? "Кейс відхилено"
                                    _ = appState.processModerationCase(caseId: item.id, approve: false, note: note)
                                    moderationNoteByCaseId[item.id] = ""
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                            }
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
    }

    private func riskTone(_ level: RiskLevel) -> AppPillTone {
        switch level {
        case .low:
            return .success
        case .medium:
            return .warning
        case .high:
            return .danger
        }
    }

    private func moderationStatusTone(_ status: ModerationCaseStatus) -> AppPillTone {
        switch status {
        case .open:
            return .warning
        case .inReview:
            return .info
        case .resolvedApproved:
            return .success
        case .resolvedRejected:
            return .danger
        }
    }

    private func auditTrailCard(_ currentUser: AppUser) -> some View {
        let eventType = selectedAuditTypeRaw == "all" ? nil : AuditEventType(rawValue: selectedAuditTypeRaw)
        let sinceDate: Date? = {
            guard selectedAuditWindowDays > 0 else { return nil }
            return Calendar.current.date(byAdding: .day, value: -selectedAuditWindowDays, to: Date())
        }()
        let events = appState.auditEventsForCurrentUser(type: eventType, since: sinceDate, limit: 24)
        let windows: [(label: String, value: Int)] = [("24г", 1), ("7д", 7), ("30д", 30), ("Все", 0)]
        let types: [(label: String, value: String)] = [("Все", "all")] + AuditEventType.allCases.map { ($0.title, $0.rawValue) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Журнал подій")
                .font(.headline)
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(types, id: \.value) { option in
                        Button(option.label) {
                            selectedAuditTypeRaw = option.value
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedAuditTypeRaw == option.value ? .purple : .secondary)
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(windows, id: \.value) { option in
                    Button(option.label) {
                        selectedAuditWindowDays = option.value
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedAuditWindowDays == option.value ? .purple : .secondary)
                }
            }

            if events.isEmpty {
                Text("Подій за вибраними фільтрами немає")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events.prefix(8)) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.caption.bold())
                        Text(event.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private func employerWalletCard(_ currentUser: AppUser) -> some View {
        if currentUser.role == .employer,
           let snapshot = appState.currentEmployerEscrowSnapshot() {
            let transactions = appState.recentWalletTransactions(for: currentUser.id, limit: 5)
            let reconciliation = appState.currentEmployerEscrowReconciliationReport()
            VStack(alignment: .leading, spacing: 10) {
                Text("Ескроу баланс")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    trustMetric(title: "Баланс", value: "\(snapshot.balance) грн", tint: .green)
                    trustMetric(title: "В резерві", value: "\(snapshot.reserved) грн", tint: .orange)
                    trustMetric(title: "Доступно", value: "\(snapshot.available) грн", tint: .purple)
                }

                HStack(spacing: 8) {
                    ForEach([5_000, 10_000, 20_000], id: \.self) { value in
                        Button("+\(value)") {
                            _ = appState.topUpCurrentEmployerWallet(by: value)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let reconciliation {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Reconciliation")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            AppStatusPill(
                                title: reconciliation.isHealthy ? "OK" : "Mismatch",
                                tone: reconciliation.isHealthy ? .success : .danger
                            )
                        }

                        Text("Ledger: \(reconciliation.expectedAvailable) грн • Wallet: \(reconciliation.actualAvailable) грн")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Розбіжність: \(reconciliation.mismatchAmount) грн")
                            .font(.caption2)
                            .foregroundStyle(reconciliation.mismatchAmount == 0 ? Color.secondary : Color.red)

                        if !reconciliation.isHealthy {
                            AppStateBanner(
                                title: "Потрібна перевірка фінансового стану",
                                message: "Запустіть звірку та перевірте останні транзакції. Якщо розбіжність зберігається, зверніться в підтримку.",
                                tone: .warning
                            )
                        }

                        Button("Запустити звірку") {
                            _ = appState.runCurrentEmployerReconciliationAudit()
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if !transactions.isEmpty {
                    Divider()
                    Text("Останні фінансові події")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ForEach(transactions) { tx in
                        HStack {
                            Text(tx.type.title)
                                .font(.caption)
                            Spacer()
                            Text(walletAmountText(tx))
                                .font(.caption.bold())
                                .foregroundStyle(tx.amount >= 0 ? .green : .red)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private func walletAmountText(_ tx: WalletTransaction) -> String {
        tx.amount >= 0 ? "+\(tx.amount) грн" : "\(tx.amount) грн"
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
        AppStatusPill(title: status.title, tone: tone)
    }

    private var tone: AppPillTone {
        switch status {
        case .scheduled:
            return .info
        case .inProgress:
            return .warning
        case .completed:
            return .accent
        case .paid:
            return .success
        }
    }
}
