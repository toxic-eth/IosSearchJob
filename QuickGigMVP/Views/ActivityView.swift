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

        return List {
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

    private var employerActivity: some View {
        let shifts = appState.shiftsForCurrentEmployer()

        return List {
            if shifts.isEmpty {
                Text("У вас пока нет размещенных смен")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shifts) { shift in
                    let shiftApplications = appState.applications(for: shift.id)
                    let pending = shiftApplications.filter { $0.status == .pending }.count
                    let accepted = shiftApplications.filter { $0.status == .accepted }.count

                    VStack(alignment: .leading, spacing: 5) {
                        Text(shift.title)
                            .font(.headline)
                        Text("Отклики: \(shiftApplications.count), ожидают: \(pending), приняты: \(accepted)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
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
