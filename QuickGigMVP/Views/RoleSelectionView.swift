import SwiftUI

struct RoleSelectionView: View {
    let onSelectRole: (UserRole) -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.9), Color.blue.opacity(0.7), Color.cyan.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("QuickGig")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text("Кто вы сегодня?")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Выберите тип аккаунта, чтобы показать только нужный интерфейс входа и регистрации.")
                    .foregroundStyle(.white.opacity(0.9))

                VStack(spacing: 12) {
                    roleCard(
                        title: "Ищу подработку",
                        subtitle: "Нахожу смены на карте, откликаюсь и работаю",
                        icon: "person.badge.clock",
                        role: .worker
                    )

                    roleCard(
                        title: "Предлагаю работу",
                        subtitle: "Создаю смены, смотрю отклики и нанимаю",
                        icon: "building.2.crop.circle",
                        role: .employer
                    )
                }
                .padding(.top, 6)

                Spacer()
            }
            .padding(20)
        }
    }

    private func roleCard(title: String, subtitle: String, icon: String, role: UserRole) -> some View {
        Button {
            onSelectRole(role)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RoleSelectionView { _ in }
}
