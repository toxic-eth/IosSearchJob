import Foundation
import Combine
import CoreLocation

final class AppState: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var users: [AppUser] = []
    @Published var shifts: [JobShift] = []
    @Published var reviews: [Review] = []

    init() {
        seedData()
    }

    var isLoggedIn: Bool {
        currentUser != nil
    }

    func login(name: String, role: UserRole) {
        if let existing = users.first(where: { $0.name.lowercased() == name.lowercased() && $0.role == role }) {
            currentUser = existing
            return
        }

        let newUser = AppUser(
            id: UUID(),
            name: name,
            role: role,
            rating: 0,
            reviewsCount: 0
        )
        users.append(newUser)
        currentUser = newUser
    }

    func logout() {
        currentUser = nil
    }

    func addShift(title: String, details: String, pay: Int, startDate: Date, endDate: Date, coordinate: CLLocationCoordinate2D) {
        guard let currentUser, currentUser.role == .employer else { return }

        shifts.append(
            JobShift(
                id: UUID(),
                title: title,
                details: details,
                pay: pay,
                startDate: startDate,
                endDate: endDate,
                coordinate: coordinate,
                employerId: currentUser.id
            )
        )
    }

    func addReview(to userId: UUID, stars: Int, comment: String) {
        guard let currentUser else { return }

        let clampedStars = min(5, max(1, stars))
        reviews.append(
            Review(
                id: UUID(),
                fromUserId: currentUser.id,
                toUserId: userId,
                stars: clampedStars,
                comment: comment,
                date: Date()
            )
        )
        recalculateRating(for: userId)
    }

    func user(by id: UUID) -> AppUser? {
        users.first(where: { $0.id == id })
    }

    func reviews(for userId: UUID) -> [Review] {
        reviews
            .filter { $0.toUserId == userId }
            .sorted { $0.date > $1.date }
    }

    private func recalculateRating(for userId: UUID) {
        let targetReviews = reviews.filter { $0.toUserId == userId }
        let count = targetReviews.count
        let rating = count == 0 ? 0 : Double(targetReviews.map(\.stars).reduce(0, +)) / Double(count)

        guard let index = users.firstIndex(where: { $0.id == userId }) else { return }
        users[index].rating = rating
        users[index].reviewsCount = count

        if currentUser?.id == userId {
            currentUser = users[index]
        }
    }

    private func seedData() {
        let employer = AppUser(
            id: UUID(),
            name: "Cafe Central",
            role: .employer,
            rating: 4.7,
            reviewsCount: 3
        )

        let worker = AppUser(
            id: UUID(),
            name: "Alex",
            role: .worker,
            rating: 4.5,
            reviewsCount: 2
        )

        users = [employer, worker]

        let calendar = Calendar.current
        let now = Date()
        let start1 = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let end1 = calendar.date(byAdding: .hour, value: 8, to: start1) ?? start1

        let start2 = calendar.date(byAdding: .day, value: 2, to: now) ?? now
        let end2 = calendar.date(byAdding: .hour, value: 6, to: start2) ?? start2

        shifts = [
            JobShift(
                id: UUID(),
                title: "Бариста на смену",
                details: "Помощь в утренний час пик",
                pay: 120,
                startDate: start1,
                endDate: end1,
                coordinate: CLLocationCoordinate2D(latitude: 55.7522, longitude: 37.6156),
                employerId: employer.id
            ),
            JobShift(
                id: UUID(),
                title: "Погрузка товара",
                details: "Склад, физическая работа",
                pay: 140,
                startDate: start2,
                endDate: end2,
                coordinate: CLLocationCoordinate2D(latitude: 55.7613, longitude: 37.6231),
                employerId: employer.id
            )
        ]

        reviews = [
            Review(
                id: UUID(),
                fromUserId: worker.id,
                toUserId: employer.id,
                stars: 5,
                comment: "Честная оплата, понятная задача",
                date: now
            )
        ]
    }
}
