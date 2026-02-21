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
                Section("Смена") {
                    Text(liveShift.title)
                        .font(.headline)
                    Text(liveShift.details)
                    Text("Оплата: $\(liveShift.pay)/ч")
                    Text("Длительность: \(liveShift.durationHours) ч")
                    Text("Дата: \(liveShift.startDate, style: .date) \(liveShift.startDate, style: .time)")
                        .foregroundStyle(.secondary)

                    let accepted = appState.acceptedApplicationsCount(for: liveShift.id)
                    HStack {
                        Text("Набор")
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
                    Section("Работодатель") {
                        Text(employer.name)
                        Text("Рейтинг: \(employer.rating, specifier: "%.1f") (\(employer.reviewsCount) отзывов)")
                            .foregroundStyle(.secondary)
                    }

                    workerActions(for: employer)
                    employerActionsIfOwner
                    reviewSection(for: employer)
                }
            }
            .navigationTitle("Детали смены")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
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
            Section("Отклик") {
                if let application = appState.application(for: liveShift.id, workerId: currentUser.id) {
                    HStack {
                        Text("Статус")
                        Spacer()
                        ApplicationStatusBadge(status: application.status)
                    }
                } else if liveShift.status == .closed {
                    Text("Набор завершен. Мест больше нет.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Откликнуться на смену") {
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

            Section("Отклики кандидатов") {
                if shiftApplications.isEmpty {
                    Text("Пока откликов нет")
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
                                    HStack {
                                        Button("Принять") {
                                            appState.updateApplicationStatus(applicationId: application.id, status: .accepted)
                                        }
                                        .buttonStyle(.borderedProminent)

                                        Button("Отклонить") {
                                            appState.updateApplicationStatus(applicationId: application.id, status: .rejected)
                                        }
                                        .buttonStyle(.bordered)
                                    }
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
            Section("Оценить работодателя") {
                Stepper("Звезды: \(stars)", value: $stars, in: 1...5)
                TextField("Короткий отзыв", text: $reviewText)
                Button("Отправить отзыв") {
                    appState.addReview(to: employer.id, stars: stars, comment: reviewText)
                    dismiss()
                }
            }
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
