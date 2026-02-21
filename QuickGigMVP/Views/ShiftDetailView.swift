import SwiftUI

struct ShiftDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let shift: JobShift

    @State private var stars = 5
    @State private var reviewText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Смена") {
                    Text(shift.title)
                        .font(.headline)
                    Text(shift.details)
                    Text("Оплата: $\(shift.pay)/ч")
                    Text("Длительность: \(shift.durationHours) ч")
                    Text("Дата: \(shift.startDate, style: .date) \(shift.startDate, style: .time)")
                        .foregroundStyle(.secondary)
                }

                if let employer = appState.user(by: shift.employerId) {
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
                if let application = appState.application(for: shift.id, workerId: currentUser.id) {
                    HStack {
                        Text("Статус")
                        Spacer()
                        ApplicationStatusBadge(status: application.status)
                    }
                } else {
                    Button("Откликнуться на смену") {
                        appState.apply(to: shift.id)
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
            currentUser.id == shift.employerId,
            currentUser.role == .employer
        {
            let shiftApplications = appState.applications(for: shift.id)

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

                                if application.status == .pending {
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
