import SwiftUI

struct ShiftDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let shift: JobShift

    @State private var stars = 5
    @State private var reviewText = ""

    private var liveShift: JobShift {
        appState.shift(by: shift.id) ?? shift
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
                    }

                    workerActions(for: employer)
                    employerActionsIfOwner
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

private struct ShiftStatusBadge: View {
    let status: ShiftStatus

    var body: some View {
        Text(status.title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status == .open ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
            .foregroundStyle(status == .open ? Color.blue : Color.gray)
            .clipShape(Capsule())
    }
}

private struct WorkProgressBadge: View {
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
