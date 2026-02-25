import SwiftUI

struct ShiftDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.dismiss) private var dismiss

    let shift: JobShift

    @State private var stars = 5
    @State private var reviewText = ""
    @State private var disputeReason = ""
    @State private var disputeResolutionNote = ""
    @State private var disputeCategory: DisputeCategory = .payment

    private var liveShift: JobShift {
        appState.shift(by: shift.id) ?? shift
    }

    private var currentUser: AppUser? {
        appState.currentUser
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Зміна") {
                    Text(liveShift.title)
                        .font(.headline)
                    Text(liveShift.details)
                    Text("Адреса: \(liveShift.address)")
                    Text("Оплата: \(liveShift.pay) грн/год")
                    Text("Тривалість: \(liveShift.durationHours) год")
                    Text("Формат: \(liveShift.workFormat.title)")
                    Text("Дата: \(liveShift.startDate, style: .date) \(liveShift.startDate, style: .time)")
                        .foregroundStyle(.secondary)

                    let accepted = appState.acceptedApplicationsCount(for: liveShift.id)
                    HStack {
                        Text("Набір")
                        Spacer()
                        Text("\(accepted)/\(liveShift.requiredWorkers)")
                            .font(.body.bold())
                    }

                    HStack {
                        Text("Статус")
                        Spacer()
                        ShiftStatusBadge(status: liveShift.status)
                    }
                }

                if let currentUser {
                    Section("Стан угоди") {
                        HStack(spacing: 8) {
                            ShiftStatusBadge(status: liveShift.status)
                            if let application = appState.application(for: liveShift.id, workerId: currentUser.id) {
                                ApplicationStatusBadge(status: application.status)
                                if application.status == .accepted {
                                    WorkProgressBadge(status: application.progressStatus)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let employer = appState.user(by: liveShift.employerId) {
                    Section("Роботодавець") {
                        HStack {
                            Text(employer.name)
                            if employer.isVerifiedEmployer {
                                Label("Перевірений", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text("Рейтинг: \(employer.rating, specifier: "%.1f") (\(employer.reviewsCount) відгуків)")
                            .foregroundStyle(.secondary)
                        Text("Надійність: \(Int(employer.reliabilityScore))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    workerActions(for: employer)
                    employerActionsIfOwner
                    paymentTransparencySection
                    disputeAndTimelineSection
                    reviewSection(for: employer)
                }
            }
            .navigationTitle("Деталі зміни")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрити") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func workerActions(for employer: AppUser) -> some View {
        if
            let currentUser = appState.currentUser,
            currentUser.role == .worker,
            currentUser.id != employer.id
        {
            Section("Відгук") {
                if let application = appState.application(for: liveShift.id, workerId: currentUser.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Статус")
                            Spacer()
                            ApplicationStatusBadge(status: application.status)
                        }
                        if application.status == .accepted {
                            HStack {
                                Text("Оплата")
                                Spacer()
                                WorkProgressBadge(status: application.progressStatus)
                            }
                            Text(appState.guaranteeStateText(for: application))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if application.status == .pending {
                            Text(appState.applicationTimeRemainingText(application))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let cooldown = appState.reminderCooldownText(for: application) {
                                Text(cooldown)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Button("Нагадати роботодавцю") {
                                appState.remindEmployer(for: application.id)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!appState.canSendReminder(for: application))
                        }
                    }
                } else if liveShift.status == .closed {
                    Text("Набір завершено. Вільних місць більше немає.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Відгукнутися на зміну") {
                        appState.apply(to: liveShift.id)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var employerActionsIfOwner: some View {
        if
            let currentUser = appState.currentUser,
            currentUser.id == liveShift.employerId,
            currentUser.role == .employer
        {
            let shiftApplications = appState.applications(for: liveShift.id)

            Section("Відгуки кандидатів") {
                if shiftApplications.isEmpty {
                    Text("Поки відгуків немає")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shiftApplications) { application in
                        if let worker = appState.user(by: application.workerId) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(worker.name)
                                        .font(.headline)
                                    Spacer()
                                    ApplicationStatusBadge(status: application.status)
                                }

                                if application.status == .pending && liveShift.status == .open {
                                    if appState.isApplicationSLACritical(application) {
                                        Label("SLA ризик: скоро спливе термін відповіді", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    HStack {
                                        Button("Прийняти") {
                                            appState.updateApplicationStatus(applicationId: application.id, status: .accepted)
                                        }
                                        .buttonStyle(.borderedProminent)

                                        Button("Відхилити") {
                                            appState.updateApplicationStatus(applicationId: application.id, status: .rejected)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                } else if application.status == .accepted {
                                    HStack {
                                        WorkProgressBadge(status: application.progressStatus)
                                        Spacer()
                                        if application.progressStatus != .paid {
                                            Button(nextActionTitle(for: application.progressStatus)) {
                                                _ = appState.advanceWorkProgressStatus(applicationId: application.id)
                                            }
                                            .buttonStyle(.borderedProminent)
                                        }
                                    }
                                    Text(appState.guaranteeStateText(for: application))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var paymentTransparencySection: some View {
        if let currentUser {
            let acceptedWorkers = max(1, appState.acceptedApplicationsCount(for: liveShift.id))
            let breakdown = appState.paymentBreakdown(for: liveShift, workersCount: acceptedWorkers)

            Section("Прозора оплата") {
                if currentUser.role == .worker {
                    let oneWorker = appState.paymentBreakdown(for: liveShift, workersCount: 1)
                    LabeledContent("Нараховано за зміну") {
                        Text("\(oneWorker.grossAmount) грн")
                    }
                    LabeledContent("Сервісний збір") {
                        Text("-\(oneWorker.workerServiceFee) грн")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("До виплати") {
                        Text("\(oneWorker.workerNetAmount) грн")
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                    if let application = appState.application(for: liveShift.id, workerId: currentUser.id),
                       let payout = appState.payoutRecord(for: application.id) {
                        LabeledContent("Payout статус") {
                            Text(payout.status.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    let oneWorker = appState.paymentBreakdown(for: liveShift, workersCount: 1)
                    LabeledContent("База до оплати") {
                        Text("\(breakdown.grossAmount) грн")
                    }
                    LabeledContent("Сервісний збір") {
                        Text("+\(breakdown.employerServiceFee) грн")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Разом до списання") {
                        Text("\(breakdown.employerTotalAmount) грн")
                            .fontWeight(.semibold)
                            .foregroundStyle(.purple)
                    }
                    LabeledContent("Потрібно на 1 працівника") {
                        Text("\(oneWorker.employerTotalAmount) грн")
                            .foregroundStyle(.secondary)
                    }
                    if let wallet = appState.currentEmployerEscrowSnapshot() {
                        LabeledContent("Ескроу доступно") {
                            Text("\(wallet.available) грн")
                                .foregroundStyle(wallet.available >= oneWorker.employerTotalAmount ? .green : .red)
                        }
                        LabeledContent("В резерві") {
                            Text("\(wallet.reserved) грн")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let firstAccepted = appState
                        .applications(for: liveShift.id)
                        .first(where: { $0.status == .accepted }),
                       let payout = appState.payoutRecord(for: firstAccepted.id) {
                        LabeledContent("Payout статус") {
                            Text(payout.status.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var disputeAndTimelineSection: some View {
        if let currentUser,
           currentUser.role == .worker,
           let application = appState.application(for: liveShift.id, workerId: currentUser.id),
           application.status == .accepted {
            Section("Виконання зміни") {
                if application.progressStatus == .scheduled {
                    Button("Check-in") {
                        _ = appState.checkIn(applicationId: application.id, coordinate: locationService.currentLocation)
                    }
                    .buttonStyle(.borderedProminent)
                } else if application.progressStatus == .inProgress {
                    Button("Check-out") {
                        _ = appState.checkOut(applicationId: application.id, coordinate: locationService.currentLocation)
                    }
                    .buttonStyle(.borderedProminent)
                }

                    if let dispute = appState.activeDispute(for: application.id) {
                        Label("Активний спір: \(dispute.status.title)", systemImage: "exclamationmark.bubble.fill")
                            .foregroundStyle(.orange)
                        Text("Категорія: \(dispute.category.title)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(dispute.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(appState.disputeSLAStatusText(dispute))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        let updates = appState.disputeUpdates(for: dispute.id)
                        if !updates.isEmpty {
                            ForEach(updates.prefix(3)) { update in
                                Text("• \(update.actorTitle): \(update.message)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Picker("Категорія", selection: $disputeCategory) {
                            ForEach(DisputeCategory.allCases) { category in
                                Text(category.title).tag(category)
                            }
                        }
                        TextField("Опишіть проблему (якщо є)", text: $disputeReason, axis: .vertical)
                            .lineLimit(2...4)
                        Button("Відкрити спір") {
                            _ = appState.openDispute(applicationId: application.id, category: disputeCategory, reason: disputeReason)
                            disputeReason = ""
                        }
                    .buttonStyle(.bordered)
                    .disabled(disputeReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            let events = appState.executionEvents(for: application.id)
            if !events.isEmpty {
                Section("Таймлайн зміни") {
                    ForEach(events.prefix(8)) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.type.title)
                                .font(.subheadline.weight(.semibold))
                            Text(event.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }

        if let currentUser, currentUser.role == .employer {
            let disputes = appState
                .applications(for: liveShift.id)
                .compactMap { app in appState.activeDispute(for: app.id).map { (app, $0) } }

            if !disputes.isEmpty {
                Section("Спори по зміні") {
                    ForEach(disputes, id: \.1.id) { item in
                        let application = item.0
                        let dispute = item.1
                        let workerName = appState.user(by: application.workerId)?.name ?? "Працівник"
                        VStack(alignment: .leading, spacing: 8) {
                            Text(workerName)
                                .font(.subheadline.weight(.semibold))
                            Text(dispute.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if dispute.status == .open {
                                Button("Взяти спір у розгляд") {
                                    _ = appState.startDisputeReview(disputeId: dispute.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                            }
                            TextField("Нотатка рішення (необов'язково)", text: $disputeResolutionNote)
                            HStack {
                                Button("На користь працівника") {
                                    _ = appState.resolveDispute(
                                        disputeId: dispute.id,
                                        inFavorOfWorker: true,
                                        note: disputeResolutionNote
                                    )
                                    disputeResolutionNote = ""
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)

                                Button("На користь роботодавця") {
                                    _ = appState.resolveDispute(
                                        disputeId: dispute.id,
                                        inFavorOfWorker: false,
                                        note: disputeResolutionNote
                                    )
                                    disputeResolutionNote = ""
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func reviewSection(for employer: AppUser) -> some View {
        if let currentUser = appState.currentUser, currentUser.id != employer.id {
            let canLeave = appState.canLeaveReview(from: currentUser.id, to: employer.id, for: liveShift.id)
            let alreadyLeft = appState.hasReview(from: currentUser.id, to: employer.id, for: liveShift.id)

            if canLeave && !alreadyLeft {
                Section("Оцінити роботодавця") {
                    Stepper("Зірки: \(stars)", value: $stars, in: 1...5)
                    TextField("Короткий відгук", text: $reviewText)
                    Button("Надіслати відгук") {
                        if appState.addReview(to: employer.id, for: liveShift.id, stars: stars, comment: reviewText) {
                            dismiss()
                        }
                    }
                }
            } else if alreadyLeft {
                Section("Оцінити роботодавця") {
                    Text("Відгук за цю зміну вже залишено")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Оцінити роботодавця") {
                    Text("Відгук стане доступним після завершення спільної зміни")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func nextActionTitle(for status: WorkProgressStatus) -> String {
        switch status {
        case .scheduled:
            return "Почати роботу"
        case .inProgress:
            return "Позначити завершено"
        case .completed:
            return "Позначити оплачено"
        case .paid:
            return "Оплачено"
        }
    }
}

private struct ApplicationStatusBadge: View {
    let status: ApplicationStatus

    var body: some View {
        AppStatusPill(title: status.title, tone: tone)
    }

    private var tone: AppPillTone {
        switch status {
        case .pending:
            return .warning
        case .accepted:
            return .success
        case .rejected:
            return .danger
        }
    }
}

private struct ShiftStatusBadge: View {
    let status: ShiftStatus

    var body: some View {
        AppStatusPill(title: status.title, tone: status == .open ? .info : .neutral)
    }
}

private struct WorkProgressBadge: View {
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
