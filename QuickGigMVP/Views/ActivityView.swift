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
                    .foregroundStyle(.white)
                Text("Прийнятих змін: \(acceptedShifts.count)")
                    .foregroundStyle(.white.opacity(0.88))
                Text("Прогноз доходу: $\(earnings)")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Усі відгуки")
                    .font(.headline)
                    .foregroundStyle(.white)

                if items.isEmpty {
                    Text("Ви ще не відгукувалися на зміни")
                        .foregroundStyle(.white.opacity(0.75))
                } else {
                    ForEach(items) { item in
                        if let shift = appState.shift(by: item.shiftId) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(shift.title)
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Text("$\(shift.pay)/год • \(shift.startDate, style: .date)")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.78))

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
                                        .tint(.cyan)
                                        .disabled(!appState.canSendReminder(for: item))

                                        if let cooldown = appState.reminderCooldownText(for: item) {
                                            Text(cooldown)
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.72))
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.white.opacity(0.06))
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
                    .foregroundStyle(.white)
                Text("Активних змін: \(shifts.filter { $0.status == .open }.count)")
                    .foregroundStyle(.white.opacity(0.86))
                Text("Прогноз виплат: $\(payroll)")
                    .font(.title3.bold())
                    .foregroundStyle(.cyan)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            VStack(alignment: .leading, spacing: 8) {
                Text("Зміни та набір")
                    .font(.headline)
                    .foregroundStyle(.white)

                if shifts.isEmpty {
                    Text("У вас поки немає опублікованих змін")
                        .foregroundStyle(.white.opacity(0.75))
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
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(accepted)/\(shift.requiredWorkers)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }

                            Text("Відгуки: \(shiftApplications.count), очікують: \(pending), статус: \(shift.status.title)")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.78))

                            if critical > 0 {
                                Label("SLA ризик: \(critical) заявок майже прострочені", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
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
