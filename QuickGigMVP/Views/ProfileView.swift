import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("preferredRole") private var preferredRoleRawValue = ""

    @State private var selectedUserId: UUID?
    @State private var stars = 5
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView()

                if let currentUser = appState.currentUser {
                    ScrollView {
                        VStack(spacing: 12) {
                            userCard(currentUser)
                            reviewComposer(currentUser)
                            recentReviews(currentUser)
                            accountActions
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Профіль")
        }
    }

    private func userCard(_ currentUser: AppUser) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.cyan.opacity(0.22))
                .frame(width: 56, height: 56)
                .overlay {
                    Text(currentUser.initials)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(currentUser.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(currentUser.role.title)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                Text("Рейтинг: \(currentUser.rating, specifier: "%.1f") (\(currentUser.reviewsCount) відгуків)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
            Spacer()
        }
        .glassCard()
    }

    private func reviewComposer(_ currentUser: AppUser) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Залишити відгук")
                .font(.headline)
                .foregroundStyle(.white)

            Picker("Кому", selection: $selectedUserId) {
                Text("Оберіть користувача").tag(UUID?.none)
                ForEach(appState.users.filter { $0.id != currentUser.id }) { user in
                    Text("\(user.name) • \(user.role.title)").tag(UUID?.some(user.id))
                }
            }
            .pickerStyle(.menu)

            Stepper("Зірки: \(stars)", value: $stars, in: 1...5)
                .foregroundStyle(.white)

            TextField("Відгук", text: $comment)
                .textFieldStyle(.roundedBorder)

            Button("Надіслати") {
                guard let selectedUserId else { return }
                appState.addReview(to: selectedUserId, stars: stars, comment: comment)
                comment = ""
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(selectedUserId == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func recentReviews(_ currentUser: AppUser) -> some View {
        let mine = appState.reviews(for: currentUser.id)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Останні відгуки")
                .font(.headline)
                .foregroundStyle(.white)

            if mine.isEmpty {
                Text("Поки немає відгуків")
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                ForEach(mine.prefix(8)) { review in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(repeating: "★", count: review.stars))
                            .foregroundStyle(.orange)
                        Text(review.comment.isEmpty ? "Без тексту" : review.comment)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                        Text(review.date, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var accountActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Акаунт")
                .font(.headline)
                .foregroundStyle(.white)

            Button("Змінити тип акаунта") {
                preferredRoleRawValue = ""
                appState.logout()
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
