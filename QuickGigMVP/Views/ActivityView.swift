import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSection: ActivitySection = .active
    @State private var reviewTarget: ReviewTarget?
    @State private var chatTarget: ChatTarget?
    @State private var disputeResolutionDraftById: [UUID: String] = [:]
    @State private var expandedDisputeIds: Set<UUID> = []
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                if let user = appState.currentUser {
                    let counts = sectionCounts(for: user)
                    ScrollView {
                        VStack(spacing: 12) {
                            summaryCard(for: user)
                            sectionPicker(counts: counts)
                            disputeHub(for: user)
                            activityContent(for: user)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Активність")
            .sheet(item: $reviewTarget) { target in
                ReviewComposerSheet(
                    target: target,
                    errorMessage: appState.authErrorMessage
                ) { stars, comment in
                    if appState.addReview(to: target.toUserId, for: target.shiftId, stars: stars, comment: comment) {
                        reviewTarget = nil
                    }
                }
            }
            .sheet(item: $chatTarget) { target in
                ConversationRoomSheet(target: target)
                    .environmentObject(appState)
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { tick in
                now = tick
            }
        }
    }

    private func summaryCard(for user: AppUser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if user.role == .worker {
                let acceptedShifts = appState.acceptedShiftsForCurrentWorker()
                let earnings = appState.projectedEarningsForCurrentWorker()

                Text("Планер змін")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Прийнятих змін: \(acceptedShifts.count)")
                    .foregroundStyle(.secondary)
                Text("Прогноз доходу: \(earnings) грн")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
            } else {
                let shifts = appState.shiftsForCurrentEmployer()
                let payroll = appState.payrollForecastForCurrentEmployer()

                Text("Панель роботодавця")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Активних змін: \(shifts.filter { $0.status == .open }.count)")
                    .foregroundStyle(.secondary)
                Text("Прогноз виплат: \(payroll) грн")
                    .font(.title3.bold())
                    .foregroundStyle(.purple)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func sectionPicker(counts: [ActivitySection: Int]) -> some View {
        Picker("Секція", selection: $selectedSection) {
            ForEach(ActivitySection.allCases) { section in
                let count = counts[section] ?? 0
                Text("\(section.title) (\(count))").tag(section)
            }
        }
        .pickerStyle(.segmented)
        .glassCard()
    }

    @ViewBuilder
    private func disputeHub(for user: AppUser) -> some View {
        let disputes = appState.disputesForCurrentUser()
        if !disputes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Спори та підтримка")
                    .font(.headline)
                    .foregroundStyle(.primary)

                ForEach(disputes.prefix(4)) { dispute in
                    let shift = appState.shift(by: dispute.shiftId)
                    let application = appState.applications.first(where: { $0.id == dispute.applicationId })
                    let workerId = application?.workerId
                    let workerName = workerId.flatMap { appState.user(by: $0)?.name } ?? "Працівник"

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(shift?.title ?? "Зміна")
                                .font(.subheadline.bold())
                            Spacer()
                            DisputeStatusBadge(status: dispute.status)
                        }

                        if user.role == .employer {
                            Text("Працівник: \(workerName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(dispute.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Категорія: \(dispute.category.title)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(appState.disputeSLAStatusText(dispute))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let seconds = appState.disputeSecondsRemaining(dispute, now: now) {
                            ProgressView(value: Double(seconds), total: 30 * 60)
                                .tint(.orange)
                        }

                        if user.role == .employer {
                            if dispute.status == .open {
                                Button("Взяти в розгляд") {
                                    _ = appState.startDisputeReview(disputeId: dispute.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                            }
                            if dispute.status == .open || dispute.status == .inReview {
                                TextField(
                                    "Нотатка рішення",
                                    text: Binding(
                                        get: { disputeResolutionDraftById[dispute.id] ?? "" },
                                        set: { disputeResolutionDraftById[dispute.id] = $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                HStack {
                                    Button("Рішення: працівник") {
                                        let note = disputeResolutionDraftById[dispute.id] ?? ""
                                        _ = appState.resolveDispute(disputeId: dispute.id, inFavorOfWorker: true, note: note)
                                        disputeResolutionDraftById[dispute.id] = ""
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)

                                    Button("Рішення: роботодавець") {
                                        let note = disputeResolutionDraftById[dispute.id] ?? ""
                                        _ = appState.resolveDispute(disputeId: dispute.id, inFavorOfWorker: false, note: note)
                                        disputeResolutionDraftById[dispute.id] = ""
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        Button(expandedDisputeIds.contains(dispute.id) ? "Сховати історію" : "Історія кейсу") {
                            if expandedDisputeIds.contains(dispute.id) {
                                expandedDisputeIds.remove(dispute.id)
                            } else {
                                expandedDisputeIds.insert(dispute.id)
                            }
                        }
                        .buttonStyle(.bordered)

                        if expandedDisputeIds.contains(dispute.id) {
                            let updates = appState.disputeUpdates(for: dispute.id)
                            if updates.isEmpty {
                                Text("Історія ще порожня")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(updates.prefix(6)) { update in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(update.actorTitle): \(update.message)")
                                            .font(.caption2)
                                        Text(update.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    @ViewBuilder
    private func activityContent(for user: AppUser) -> some View {
        if user.role == .worker {
            workerActivityContent
        } else {
            employerActivityContent
        }
    }

    private var workerActivityContent: some View {
        let items = workerItems(for: selectedSection)
        return VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("У цьому розділі поки немає записів")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(item.shift.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            ActivityStatusBadge(status: item.application.status)
                        }

                        Text(item.shift.details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Text("\(item.shift.pay) грн/год • \(item.shift.durationHours) год")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(item.shift.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Роботодавець: \(item.employer.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Надійність роботодавця: \(Int(item.employer.reliabilityScore))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if item.application.status == .accepted {
                            HStack {
                                Text("Оплата")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                ActivityProgressBadge(status: item.application.progressStatus)
                            }
                            if let payout = appState.payoutRecord(for: item.application.id) {
                                HStack {
                                    Text("Payout")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    PayoutStatusBadge(status: payout.status)
                                }
                            }
                            Text(appState.guaranteeStateText(for: item.application))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if selectedSection == .pending && item.application.status == .pending {
                            pendingReminderRow(for: item.application)
                        }

                        quickChatRow(shift: item.shift, workerId: item.application.workerId, counterpartName: item.employer.name)

                        if selectedSection == .completed {
                            completedReviewRow(
                                shift: item.shift,
                                fromUserId: item.application.workerId,
                                toUserId: item.shift.employerId,
                                actionTitle: "Оцінити роботодавця"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        if selectedSection == .completed {
                            openReviewIfAvailable(
                                shift: item.shift,
                                fromUserId: item.application.workerId,
                                toUserId: item.shift.employerId
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var employerActivityContent: some View {
        let items = employerItems(for: selectedSection)
        return VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("У цьому розділі поки немає записів")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(item.shift.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Spacer()
                            ActivityStatusBadge(status: item.application.status)
                        }

                        Text("Кандидат: \(item.worker.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Надійність кандидата: \(Int(item.worker.reliabilityScore))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("\(item.shift.pay) грн/год • \(item.shift.durationHours) год • \(item.shift.workFormat.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(item.shift.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if item.application.status == .accepted {
                            HStack {
                                Text("Виплата")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                ActivityProgressBadge(status: item.application.progressStatus)
                            }
                            if let payout = appState.payoutRecord(for: item.application.id) {
                                HStack {
                                    Text("Payout")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    PayoutStatusBadge(status: payout.status)
                                }
                            }
                        }

                        if selectedSection == .pending && appState.isApplicationSLACritical(item.application) {
                            Label("SLA ризик: скоро спливе термін відповіді", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        quickChatRow(shift: item.shift, workerId: item.worker.id, counterpartName: item.worker.name)

                        if selectedSection == .completed {
                            completedReviewRow(
                                shift: item.shift,
                                fromUserId: item.shift.employerId,
                                toUserId: item.worker.id,
                                actionTitle: "Оцінити працівника"
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        if selectedSection == .completed {
                            openReviewIfAvailable(
                                shift: item.shift,
                                fromUserId: item.shift.employerId,
                                toUserId: item.worker.id
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func pendingReminderRow(for application: ShiftApplication) -> some View {
        HStack {
            Button("Нагадати роботодавцю") {
                appState.remindEmployer(for: application.id)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(!appState.canSendReminder(for: application))

            if let cooldown = appState.reminderCooldownText(for: application) {
                Text(cooldown)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(appState.applicationTimeRemainingText(application))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func completedReviewRow(shift: JobShift, fromUserId: UUID, toUserId: UUID, actionTitle: String) -> some View {
        if appState.hasReview(from: fromUserId, to: toUserId, for: shift.id) {
            Label("Відгук вже залишено", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if appState.canLeaveReview(from: fromUserId, to: toUserId, for: shift.id) {
            Button(actionTitle) {
                reviewTarget = ReviewTarget(
                    shiftId: shift.id,
                    toUserId: toUserId,
                    shiftTitle: shift.title,
                    shiftAddress: shift.address
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
    }

    private func workerItems(for section: ActivitySection) -> [WorkerActivityItem] {
        let now = Date()
        let allItems = appState.applicationsForCurrentWorker().compactMap { application -> WorkerActivityItem? in
            guard let shift = appState.shift(by: application.shiftId),
                  let employer = appState.user(by: shift.employerId) else { return nil }
            return WorkerActivityItem(application: application, shift: shift, employer: employer)
        }

        switch section {
        case .active:
            return allItems
                .filter {
                    $0.application.status == .accepted &&
                    $0.application.progressStatus != .completed &&
                    $0.application.progressStatus != .paid &&
                    $0.shift.endDate > now
                }
                .sorted { $0.shift.startDate < $1.shift.startDate }
        case .pending:
            return allItems
                .filter { $0.application.status == .pending }
                .sorted { $0.application.createdAt > $1.application.createdAt }
        case .completed:
            return allItems
                .filter {
                    $0.application.status == .accepted &&
                    (
                        $0.application.progressStatus == .completed ||
                        $0.application.progressStatus == .paid ||
                        $0.shift.endDate <= now
                    )
                }
                .sorted { $0.shift.endDate > $1.shift.endDate }
        }
    }

    private func employerItems(for section: ActivitySection) -> [EmployerActivityItem] {
        let now = Date()
        guard let currentUser = appState.currentUser else { return [] }

        var allItems: [EmployerActivityItem] = []
        for shift in appState.shiftsForCurrentEmployer() where shift.employerId == currentUser.id {
            let shiftApplications = appState.applications(for: shift.id)
            for application in shiftApplications {
                guard let worker = appState.user(by: application.workerId) else { continue }
                allItems.append(EmployerActivityItem(application: application, shift: shift, worker: worker))
            }
        }

        switch section {
        case .active:
            return allItems
                .filter {
                    $0.application.status == .accepted &&
                    $0.application.progressStatus != .completed &&
                    $0.application.progressStatus != .paid &&
                    $0.shift.endDate > now
                }
                .sorted { $0.shift.startDate < $1.shift.startDate }
        case .pending:
            return allItems
                .filter { $0.application.status == .pending }
                .sorted { $0.application.createdAt > $1.application.createdAt }
        case .completed:
            return allItems
                .filter {
                    $0.application.status == .accepted &&
                    (
                        $0.application.progressStatus == .completed ||
                        $0.application.progressStatus == .paid ||
                        $0.shift.endDate <= now
                    )
                }
                .sorted { $0.shift.endDate > $1.shift.endDate }
        }
    }

    private func openReviewIfAvailable(shift: JobShift, fromUserId: UUID, toUserId: UUID) {
        guard !appState.hasReview(from: fromUserId, to: toUserId, for: shift.id) else { return }
        guard appState.canLeaveReview(from: fromUserId, to: toUserId, for: shift.id) else { return }
        reviewTarget = ReviewTarget(
            shiftId: shift.id,
            toUserId: toUserId,
            shiftTitle: shift.title,
            shiftAddress: shift.address
        )
    }

    @ViewBuilder
    private func quickChatRow(shift: JobShift, workerId: UUID, counterpartName: String) -> some View {
        let existingConversation = appState.conversation(for: shift.id, workerId: workerId)
        HStack {
            Button("Відкрити чат") {
                guard let conversation = appState.ensureConversation(shiftId: shift.id, workerId: workerId) else { return }
                chatTarget = ChatTarget(conversationId: conversation.id, shiftTitle: shift.title, counterpartName: counterpartName)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)

            let unread = existingConversation.map { appState.unreadMessagesCount(in: $0.id) } ?? 0
            if unread > 0 {
                Text("\(unread) нових")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
        }
    }

    private func sectionCounts(for user: AppUser) -> [ActivitySection: Int] {
        user.role == .worker ? workerSectionCounts() : employerSectionCounts()
    }

    private func workerSectionCounts() -> [ActivitySection: Int] {
        let now = Date()
        var counts: [ActivitySection: Int] = [.active: 0, .pending: 0, .completed: 0]

        for application in appState.applicationsForCurrentWorker() {
            guard let shift = appState.shift(by: application.shiftId) else { continue }
            switch application.status {
            case .pending:
                counts[.pending, default: 0] += 1
            case .accepted:
                if application.progressStatus == .completed || application.progressStatus == .paid || shift.endDate <= now {
                    counts[.completed, default: 0] += 1
                } else {
                    counts[.active, default: 0] += 1
                }
            case .rejected:
                break
            }
        }

        return counts
    }

    private func employerSectionCounts() -> [ActivitySection: Int] {
        let now = Date()
        var counts: [ActivitySection: Int] = [.active: 0, .pending: 0, .completed: 0]

        for shift in appState.shiftsForCurrentEmployer() {
            for application in appState.applications(for: shift.id) {
                switch application.status {
                case .pending:
                    counts[.pending, default: 0] += 1
                case .accepted:
                    if application.progressStatus == .completed || application.progressStatus == .paid || shift.endDate <= now {
                        counts[.completed, default: 0] += 1
                    } else {
                        counts[.active, default: 0] += 1
                    }
                case .rejected:
                    break
                }
            }
        }

        return counts
    }
}

private enum ActivitySection: String, CaseIterable, Identifiable {
    case active
    case pending
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:
            return "Активні"
        case .pending:
            return "Очікують"
        case .completed:
            return "Виконані"
        }
    }
}

private struct WorkerActivityItem: Identifiable {
    let application: ShiftApplication
    let shift: JobShift
    let employer: AppUser
    var id: UUID { application.id }
}

private struct EmployerActivityItem: Identifiable {
    let application: ShiftApplication
    let shift: JobShift
    let worker: AppUser
    var id: UUID { application.id }
}

private struct ReviewTarget: Identifiable {
    let shiftId: UUID
    let toUserId: UUID
    let shiftTitle: String
    let shiftAddress: String

    var id: String {
        "\(shiftId.uuidString)-\(toUserId.uuidString)"
    }
}

private struct ReviewComposerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: ReviewTarget
    let errorMessage: String?
    let onSubmit: (_ stars: Int, _ comment: String) -> Void

    @State private var stars = 5
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(target.shiftTitle)
                    .font(.headline)
                Text(target.shiftAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { index in
                        Button {
                            stars = index
                        } label: {
                            Image(systemName: index <= stars ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(index <= stars ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("Коментар (необов'язково)", text: $comment, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button("Надіслати відгук") {
                    onSubmit(stars, comment)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)

                Spacer()
            }
            .padding(16)
            .navigationTitle("Оцінка")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрити") { dismiss() }
                }
            }
        }
    }
}

private struct ChatTarget: Identifiable {
    let conversationId: UUID
    let shiftTitle: String
    let counterpartName: String

    var id: UUID { conversationId }
}

struct CommunicationHubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedChat: ChatTarget?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(appState.conversationsForCurrentUser()) { conversation in
                            conversationRow(conversation)
                        }
                        if appState.conversationsForCurrentUser().isEmpty {
                            Text("Ще немає діалогів. Відкрийте чат зі сторінки активностей.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Чати")
            .sheet(item: $selectedChat) { target in
                ConversationRoomSheet(target: target)
                    .environmentObject(appState)
            }
        }
    }

    private func conversationRow(_ conversation: ShiftConversation) -> some View {
        let shift = appState.shift(by: conversation.shiftId)
        let me = appState.currentUser
        let counterpartId = conversation.employerId == me?.id ? conversation.workerId : conversation.employerId
        let counterpart = appState.user(by: counterpartId)
        let lastMessage = appState.lastMessage(in: conversation.id)
        let unread = appState.unreadMessagesCount(in: conversation.id)
        return Button {
            selectedChat = ChatTarget(
                conversationId: conversation.id,
                shiftTitle: shift?.title ?? "Зміна",
                counterpartName: counterpart?.name ?? "Користувач"
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(counterpart?.name ?? "Користувач")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(shift?.title ?? "Зміна")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }

                Text(lastMessage?.text ?? "Почніть діалог")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .glassCard()
    }
}

private struct ConversationRoomSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let target: ChatTarget
    @State private var messageText = ""
    @State private var showOfferComposer = false
    @State private var offerPay = "200"
    @State private var offerWorkers = "1"
    @State private var offerStart = Date()
    @State private var offerEnd = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
    @State private var offerAddress = ""

    private var messages: [ChatMessage] {
        appState.messages(for: target.conversationId)
    }

    private var offersById: [UUID: DealOffer] {
        Dictionary(uniqueKeysWithValues: appState.offers(for: target.conversationId).map { ($0.id, $0) })
    }

    private var canSendOffer: Bool {
        guard let current = appState.currentUser,
              let convo = appState.conversations.first(where: { $0.id == target.conversationId }) else { return false }
        return current.id == convo.employerId || current.id == convo.workerId
    }

    private var isBlocked: Bool {
        appState.isConversationBlocked(target.conversationId)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(messages) { message in
                                messageRow(message)
                                    .id(message.id)
                            }
                        }
                        .padding(12)
                    }
                    .onAppear {
                        appState.markConversationRead(target.conversationId)
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: messages.count) { _, _ in
                        appState.markConversationRead(target.conversationId)
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                VStack(spacing: 8) {
                    if canSendOffer && !isBlocked {
                        Button("Надіслати оффер") {
                            showOfferComposer = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }

                    HStack(spacing: 8) {
                        TextField("Повідомлення", text: $messageText)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isBlocked)

                        Button("Надіслати") {
                            if appState.sendMessage(conversationId: target.conversationId, text: messageText) {
                                messageText = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(isBlocked)
                    }
                    if isBlocked {
                        Text("Діалог заблоковано. Надсилання нових повідомлень недоступне.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
            }
            .navigationTitle(target.counterpartName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(target.shiftTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Поскаржитись") {
                            appState.reportConversationIssue(target.conversationId, reason: "Некоректна поведінка в чаті")
                        }
                        Button("Заблокувати діалог", role: .destructive) {
                            appState.blockCurrentCounterparty(in: target.conversationId)
                        }
                        Button("Закрити") { dismiss() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showOfferComposer) {
                NavigationStack {
                    Form {
                        Section("Умови офферу") {
                            TextField("Оплата грн/год", text: $offerPay)
                                .keyboardType(.numberPad)
                            TextField("Кількість працівників", text: $offerWorkers)
                                .keyboardType(.numberPad)
                            DatePicker("Початок", selection: $offerStart)
                            DatePicker("Завершення", selection: $offerEnd)
                            TextField("Адреса", text: $offerAddress)
                        }
                    }
                    .navigationTitle("Новий оффер")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Скасувати") { showOfferComposer = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Надіслати") {
                                let pay = Int(offerPay) ?? 0
                                let workers = Int(offerWorkers) ?? 1
                                if appState.sendOffer(
                                    conversationId: target.conversationId,
                                    payPerHour: pay,
                                    startDate: offerStart,
                                    endDate: offerEnd,
                                    address: offerAddress,
                                    workersCount: workers
                                ) {
                                    showOfferComposer = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        let myId = appState.currentUser?.id
        let isMine = message.senderRole == .user && message.senderId == myId
        HStack {
            if isMine { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 6) {
                if message.senderRole == .system {
                    Text("Система")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let offerId = message.offerId, let offer = offersById[offerId] {
                    offerCard(offer)
                }

                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(isMine ? Color.purple.opacity(0.20) : Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if !isMine { Spacer(minLength: 32) }
        }
    }

    @ViewBuilder
    private func offerCard(_ offer: DealOffer) -> some View {
        let currentUserId = appState.currentUser?.id
        VStack(alignment: .leading, spacing: 6) {
            Text("Оффер • \(offer.status.title)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("\(offer.proposedPayPerHour) грн/год • \(offer.proposedWorkersCount) працівн.")
                .font(.subheadline.bold())
            Text(offer.proposedAddress)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(offer.proposedStartDate.formatted(date: .abbreviated, time: .shortened)) - \(offer.proposedEndDate.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if offer.status == .pending && offer.toUserId == currentUserId {
                HStack {
                    Button("Прийняти") {
                        _ = appState.respondToOffer(offerId: offer.id, accept: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    Button("Відхилити") {
                        _ = appState.respondToOffer(offerId: offer.id, accept: false)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ActivityStatusBadge: View {
    let status: ApplicationStatus

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
        case .pending:
            return .orange.opacity(0.2)
        case .accepted:
            return .green.opacity(0.2)
        case .rejected:
            return .red.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch status {
        case .pending:
            return .orange
        case .accepted:
            return .green
        case .rejected:
            return .red
        }
    }
}

private struct ActivityProgressBadge: View {
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

private struct DisputeStatusBadge: View {
    let status: ShiftDisputeStatus

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
        case .open:
            return .orange.opacity(0.2)
        case .inReview:
            return .blue.opacity(0.2)
        case .resolvedForWorker, .resolvedForEmployer:
            return .green.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch status {
        case .open:
            return .orange
        case .inReview:
            return .blue
        case .resolvedForWorker, .resolvedForEmployer:
            return .green
        }
    }
}

private struct PayoutStatusBadge: View {
    let status: PayoutStatus

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
        case .reserved:
            return .blue.opacity(0.2)
        case .onHold:
            return .orange.opacity(0.2)
        case .pendingRelease:
            return .purple.opacity(0.2)
        case .paid:
            return .green.opacity(0.2)
        case .canceled:
            return .red.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch status {
        case .reserved:
            return .blue
        case .onHold:
            return .orange
        case .pendingRelease:
            return .purple
        case .paid:
            return .green
        case .canceled:
            return .red
        }
    }
}
