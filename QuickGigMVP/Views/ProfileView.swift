import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedUserId: UUID?
    @State private var stars = 5
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            Form {
                if let currentUser = appState.currentUser {
                    Section {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 54, height: 54)
                                .overlay {
                                    Text(currentUser.initials)
                                        .font(.headline)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentUser.name)
                                    .font(.headline)
                                Text(currentUser.role.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Рейтинг: \(currentUser.rating, specifier: "%.1f") (\(currentUser.reviewsCount) отзывов)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    Section("Оставить отзыв") {
                        Picker("Кому", selection: $selectedUserId) {
                            Text("Выберите пользователя").tag(UUID?.none)
                            ForEach(appState.users.filter { $0.id != currentUser.id }) { user in
                                Text("\(user.name) • \(user.role.title)").tag(UUID?.some(user.id))
                            }
                        }

                        Stepper("Звезды: \(stars)", value: $stars, in: 1...5)
                        TextField("Отзыв", text: $comment)

                        Button("Отправить") {
                            guard let selectedUserId else { return }
                            appState.addReview(to: selectedUserId, stars: stars, comment: comment)
                            comment = ""
                        }
                    }

                    Section("Последние отзывы") {
                        let mine = appState.reviews(for: currentUser.id)
                        if mine.isEmpty {
                            Text("Пока нет отзывов")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(mine.prefix(8)) { review in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(repeating: "★", count: review.stars))
                                        .foregroundStyle(.orange)
                                    Text(review.comment.isEmpty ? "Без текста" : review.comment)
                                        .font(.subheadline)
                                    Text(review.date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Профиль")
        }
    }
}
