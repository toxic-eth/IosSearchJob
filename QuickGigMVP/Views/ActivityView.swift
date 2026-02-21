import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if let user = appState.currentUser {
                    if user.role == .worker {
                        workerActivity
                    } else {
                        employerActivity
                    }
                }
            }
            .navigationTitle("Активность")
        }
    }

    private var workerActivity: some View {
        let items = appState.applicationsForCurrentWorker()
        let acceptedShifts = appState.acceptedShiftsForCurrentWorker()
        let earnings = appState.projectedEarningsForCurrentWorker()

        return List {
            Section("Планер смен") {
                Text("Принятых смен: \(acceptedShifts.count)")
                Text("Прогноз дохода: $\(earnings)")
                    .font(.headline)
                    .foregroundStyle(.green)

                ForEach(acceptedShifts.prefix(5)) { shift in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(shift.title)
                            Text(shift.startDate, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("$\(shift.pay * shift.durationHours)")
                            .font(.subheadline.bold())
                    }
                }
            }

            Section("Все отклики") {
                if items.isEmpty {
                    Text("Вы еще не откликались на смены")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        if let shift = appState.shift(by: item.shiftId) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(shift.title)
                                    .font(.headline)
                                Text("$\(shift.pay)/ч • \(shift.startDate, style: .date)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(item.status.title)
                                    .font(.caption.bold())
                                    .foregroundStyle(statusColor(item.status))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    private var employerActivity: some View {
        let shifts = appState.shiftsForCurrentEmployer()
        let payroll = appState.payrollForecastForCurrentEmployer()

        return List {
            Section("Панель работодателя") {
                Text("Активных смен: \(shifts.filter { $0.status == .open }.count)")
                Text("Прогноз выплат: $\(payroll)")
                    .font(.headline)
                    .foregroundStyle(.indigo)
            }

            Section("Смены и набор") {
                if shifts.isEmpty {
                    Text("У вас пока нет размещенных смен")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shifts) { shift in
                        let shiftApplications = appState.applications(for: shift.id)
                        let pending = shiftApplications.filter { $0.status == .pending }.count
                        let accepted = appState.acceptedApplicationsCount(for: shift.id)

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(shift.title)
                                    .font(.headline)
                                Spacer()
                                Text("\(accepted)/\(shift.requiredWorkers)")
                                    .font(.caption.bold())
                            }
                            Text("Отклики: \(shiftApplications.count), ожидают: \(pending), статус: \(shift.status.title)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func statusColor(_ status: ApplicationStatus) -> Color {
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
