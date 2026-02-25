import SwiftUI

enum ShiftCardLayout {
    case compact
    case expanded
}

struct ShiftCardView: View {
    let shift: JobShift
    let employer: AppUser?
    let accepted: Int
    let distanceKm: Double?
    let layout: ShiftCardLayout
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: layout == .compact ? 7 : 9) {
                HStack {
                    Text(shift.title)
                        .font(layout == .compact ? .subheadline.weight(.semibold) : .headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    statusPill
                }

                Text(shift.details)
                    .font(layout == .compact ? .caption : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(layout == .compact ? 1 : 2)

                Text(shift.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                metaRow

                if let employer {
                    trustRow(employer)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private var statusPill: some View {
        AppStatusPill(
            title: shift.status.title,
            tone: shift.status == .open ? .accent : .neutral
        )
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            Label("\(shift.pay) грн/год", systemImage: "dollarsign.circle")
            Label("\(shift.durationHours) год", systemImage: "clock")
            Label(shift.workFormat.title, systemImage: shift.workFormat == .online ? "wifi" : "mappin.and.ellipse")
            Label("\(accepted)/\(shift.requiredWorkers)", systemImage: "person.3")
            if let distanceKm {
                Label("\(distanceKm, specifier: "%.1f") км", systemImage: "road.lanes")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func trustRow(_ employer: AppUser) -> some View {
        HStack(spacing: 8) {
            Label(employer.name, systemImage: "building.2")
                .lineLimit(1)
            if employer.isVerifiedEmployer {
                Label("Перевірено", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.purple)
            }
            Text("• \(Int(employer.reliabilityScore))%")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
