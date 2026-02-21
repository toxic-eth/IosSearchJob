import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                if let user = appState.currentUser {
                    ScrollView {
                        VStack(spacing: 12) {
                            if user.role == .worker {
                                workerActivity
                            } else {
                                employerActivity
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Активність")
        }
    }

    private var workerActivity: some View {
        let items = appState.applicationsForCurrentWorker()
        let acceptedShifts = appState.acceptedShiftsForCurrentWorker()
        let earnings = appState.projectedEarningsForCurrentWorker()

        return VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Планер змін")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Прийнятих змін: \(acceptedShifts.count)")
                    .foregroundStyle(.secondary)
                Text("Прогноз доходу: \(earnings) грн")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Усі відгуки")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if items.isEmpty {
                    Text("Ви ще не відгукувалися на зміни")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        if let shift = appState.shift(by: item.shiftId) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(shift.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text("\(shift.pay) грн/год • \(shift.startDate, style: .date)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Text(item.status.title)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(statusColor(item.status).opacity(0.2))
                                        .clipShape(Capsule())
                                        .foregroundStyle(statusColor(item.status))

                                    Spacer()

                                    if item.status == .pending {
                                        Text(appState.applicationTimeRemainingText(item))
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }

                                if item.status == .pending {
                                    HStack {
                                        Button("Нагадати роботодавцю") {
                                            appState.remindEmployer(for: item.id)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.purple)
                                        .disabled(!appState.canSendReminder(for: item))

                                        if let cooldown = appState.reminderCooldownText(for: item) {
                                            Text(cooldown)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
    }

    private var employerActivity: some View {
        let shifts = appState.shiftsForCurrentEmployer()
        let payroll = appState.payrollForecastForCurrentEmployer()

        return VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Панель роботодавця")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Активних змін: \(shifts.filter { $0.status == .open }.count)")
                    .foregroundStyle(.secondary)
                Text("Прогноз виплат: \(payroll) грн")
                    .font(.title3.bold())
                    .foregroundStyle(.purple)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Зміни та набір")
                    .font(.headline)
                    .foregroundStyle(.primary)

                if shifts.isEmpty {
                    Text("У вас поки немає опублікованих змін")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shifts) { shift in
                        let shiftApplications = appState.applications(for: shift.id)
                        let pending = shiftApplications.filter { $0.status == .pending }.count
                        let accepted = appState.acceptedApplicationsCount(for: shift.id)
                        let critical = shiftApplications.filter { appState.isApplicationSLACritical($0) }.count

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(shift.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(accepted)/\(shift.requiredWorkers)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                            }

                            Text("Відгуки: \(shiftApplications.count), очікують: \(pending), статус: \(shift.status.title)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if critical > 0 {
                                Label("SLA ризик: \(critical) заявок майже прострочені", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
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
