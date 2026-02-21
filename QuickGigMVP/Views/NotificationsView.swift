import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState

    private var items: [InAppNotification] {
        appState.currentUserNotifications()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                if items.isEmpty {
                    ContentUnavailableView(
                        "Поки тихо",
                        systemImage: "bell.slash",
                        description: Text("Тут з'являться рішення по відгуках, нагадування та системні оновлення.")
                    )
                    .foregroundStyle(.primary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(items) { item in
                                notificationCard(item)
                                    .onTapGesture {
                                        appState.markNotificationAsRead(item.id)
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Сповіщення")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Прочитати всі") {
                        appState.markAllNotificationsAsReadForCurrentUser()
                    }
                    .disabled(items.isEmpty)
                }
            }
        }
    }

    private func notificationCard(_ item: InAppNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color(for: item.kind).opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: icon(for: item.kind))
                        .foregroundStyle(color(for: item.kind))
                        .font(.footnote.bold())
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if !item.isRead {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(item.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(item.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .glassCard()
    }

    private func icon(for kind: NotificationKind) -> String {
        switch kind {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private func color(for kind: NotificationKind) -> Color {
        switch kind {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
