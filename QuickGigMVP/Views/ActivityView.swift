import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSection: ActivitySection = .active
    @State private var reviewTarget: ReviewTarget?

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

                        if item.application.status == .accepted {
                            HStack {
                                Text("Оплата")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                ActivityProgressBadge(status: item.application.progressStatus)
                            }
                            Text(appState.guaranteeStateText(for: item.application))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if selectedSection == .pending && item.application.status == .pending {
                            pendingReminderRow(for: item.application)
                        }

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
                        }

                        if selectedSection == .pending && appState.isApplicationSLACritical(item.application) {
                            Label("SLA ризик: скоро спливе термін відповіді", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

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
