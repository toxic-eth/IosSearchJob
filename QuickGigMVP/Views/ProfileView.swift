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
                    Section("Мой профиль") {
                        Text(currentUser.name)
                        Text("Роль: \(currentUser.title)")
                        Text("Рейтинг: \(currentUser.rating, specifier: "%.1f") (\(currentUser.reviewsCount) отзывов)")
                    }

                    Section("Оставить отзыв") {
                        Picker("Кому", selection: $selectedUserId) {
                            Text("Выберите пользователя").tag(UUID?.none)
                            ForEach(appState.users.filter { $0.id != currentUser.id }) { user in
                                Text("\(user.name) • \(user.title)").tag(UUID?.some(user.id))
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

                    Section("Последние отзывы обо мне") {
                        let mine = appState.reviews(for: currentUser.id)
                        if mine.isEmpty {
                            Text("Пока нет отзывов")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(mine.prefix(5)) { review in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(repeating: "★", count: review.stars))
                                    Text(review.comment.isEmpty ? "Без текста" : review.comment)
                                        .font(.subheadline)
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

private extension AppUser {
    var title: String {
        role == .worker ? "Работник" : "Работодатель"
    }
}
