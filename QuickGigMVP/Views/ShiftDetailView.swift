import SwiftUI

struct ShiftDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let shift: JobShift

    @State private var stars = 5
    @State private var reviewText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Смена") {
                    Text(shift.title)
                        .font(.headline)
                    Text(shift.details)
                    Text("Оплата: $\(shift.pay)/ч")
                    Text("Длительность: \(shift.durationHours) ч")
                }

                if let employer = appState.user(by: shift.employerId) {
                    Section("Работодатель") {
                        Text(employer.name)
                        Text("Рейтинг: \(employer.rating, specifier: "%.1f") (\(employer.reviewsCount) отзывов)")
                            .foregroundStyle(.secondary)
                    }

                    if appState.currentUser?.id != employer.id {
                        Section("Оценить работодателя") {
                            Stepper("Звезды: \(stars)", value: $stars, in: 1...5)
                            TextField("Короткий отзыв", text: $reviewText)
                            Button("Отправить отзыв") {
                                appState.addReview(to: employer.id, stars: stars, comment: reviewText)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Детали")
        }
    }
}
