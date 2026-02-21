import Foundation
import Combine
import CoreLocation

final class AppState: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var users: [AppUser] = []
    @Published var shifts: [JobShift] = []
    @Published var reviews: [Review] = []
    @Published var applications: [ShiftApplication] = []
    @Published var authErrorMessage: String?
    @Published private(set) var shouldRequestLocationPermission = false

    init() {
        seedData()
    }

    var isLoggedIn: Bool {
        currentUser != nil
    }

    func consumeLocationPermissionRequest() -> Bool {
        guard shouldRequestLocationPermission else { return false }
        shouldRequestLocationPermission = false
        return true
    }

    func register(name: String, email: String, password: String, role: UserRole) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !normalizedName.isEmpty else {
            authErrorMessage = "Введите имя или название компании"
            return false
        }

        guard normalizedEmail.contains("@") && normalizedEmail.contains(".") else {
            authErrorMessage = "Введите корректный email"
            return false
        }

        guard password.count >= 6 else {
            authErrorMessage = "Пароль должен быть минимум 6 символов"
            return false
        }

        if users.contains(where: { $0.email.lowercased() == normalizedEmail }) {
            authErrorMessage = "Пользователь с таким email уже существует"
            return false
        }

        let user = AppUser(
            id: UUID(),
            name: normalizedName,
            email: normalizedEmail,
            password: password,
            role: role,
            rating: 0,
            reviewsCount: 0
        )

        users.append(user)
        currentUser = user
        shouldRequestLocationPermission = true
        authErrorMessage = nil
        return true
    }

    func login(email: String, password: String, expectedRole: UserRole? = nil) -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard let user = users.first(where: { $0.email.lowercased() == normalizedEmail }) else {
            authErrorMessage = "Пользователь не найден"
            return false
        }

        guard user.password == password else {
            authErrorMessage = "Неверный пароль"
            return false
        }

        if let expectedRole, user.role != expectedRole {
            authErrorMessage = expectedRole == .worker
                ? "Этот аккаунт зарегистрирован как работодатель"
                : "Этот аккаунт зарегистрирован как работник"
            return false
        }

        currentUser = user
        shouldRequestLocationPermission = false
        authErrorMessage = nil
        return true
    }

    func logout() {
        currentUser = nil
        shouldRequestLocationPermission = false
    }

    func addShift(title: String, details: String, pay: Int, startDate: Date, endDate: Date, coordinate: CLLocationCoordinate2D, requiredWorkers: Int) {
        guard let currentUser, currentUser.role == .employer else { return }
        let finalCoordinate = UkraineRegion.contains(coordinate) ? coordinate : UkraineRegion.center

        shifts.append(
            JobShift(
                id: UUID(),
                title: title,
                details: details,
                pay: pay,
                startDate: startDate,
                endDate: endDate,
                coordinate: finalCoordinate,
                employerId: currentUser.id,
                requiredWorkers: max(1, requiredWorkers),
                status: .open
            )
        )
    }

    func apply(to shiftId: UUID) {
        guard let currentUser, currentUser.role == .worker else { return }
        guard let shift = shift(by: shiftId), shift.status == .open, !isShiftFull(shift) else { return }
        guard !applications.contains(where: { $0.shiftId == shiftId && $0.workerId == currentUser.id }) else { return }

        applications.append(
            ShiftApplication(
                id: UUID(),
                shiftId: shiftId,
                workerId: currentUser.id,
                status: .pending,
                createdAt: Date()
            )
        )
    }

    func updateApplicationStatus(applicationId: UUID, status: ApplicationStatus) {
        guard let index = applications.firstIndex(where: { $0.id == applicationId }) else { return }

        let shiftId = applications[index].shiftId
        if status == .accepted,
           let shift = shift(by: shiftId),
           acceptedApplicationsCount(for: shift.id) >= shift.requiredWorkers,
           applications[index].status != .accepted {
            return
        }

        applications[index].status = status
        syncShiftCapacity(for: shiftId)
    }

    func application(for shiftId: UUID, workerId: UUID) -> ShiftApplication? {
        applications.first(where: { $0.shiftId == shiftId && $0.workerId == workerId })
    }

    func applications(for shiftId: UUID) -> [ShiftApplication] {
        applications
            .filter { $0.shiftId == shiftId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func applicationsForCurrentWorker() -> [ShiftApplication] {
        guard let currentUser else { return [] }
        return applications
            .filter { $0.workerId == currentUser.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func acceptedShiftsForCurrentWorker() -> [JobShift] {
        guard let currentUser else { return [] }

        let acceptedIds = applications
            .filter { $0.workerId == currentUser.id && $0.status == .accepted }
            .map(\.shiftId)

        return shifts
            .filter { acceptedIds.contains($0.id) }
            .sorted { $0.startDate < $1.startDate }
    }

    func projectedEarningsForCurrentWorker() -> Int {
        acceptedShiftsForCurrentWorker()
            .filter { $0.startDate >= Date() }
            .map { $0.pay * $0.durationHours }
            .reduce(0, +)
    }

    func shiftsForCurrentEmployer() -> [JobShift] {
        guard let currentUser else { return [] }
        return shifts
            .filter { $0.employerId == currentUser.id }
            .sorted { $0.startDate < $1.startDate }
    }

    func payrollForecastForCurrentEmployer() -> Int {
        shiftsForCurrentEmployer()
            .map { shift in shift.pay * shift.durationHours * acceptedApplicationsCount(for: shift.id) }
            .reduce(0, +)
    }

    func acceptedApplicationsCount(for shiftId: UUID) -> Int {
        applications.filter { $0.shiftId == shiftId && $0.status == .accepted }.count
    }

    func isShiftFull(_ shift: JobShift) -> Bool {
        acceptedApplicationsCount(for: shift.id) >= shift.requiredWorkers
    }

    func addReview(to userId: UUID, stars: Int, comment: String) {
        guard let currentUser, currentUser.id != userId else { return }

        let clampedStars = min(5, max(1, stars))
        reviews.append(
            Review(
                id: UUID(),
                fromUserId: currentUser.id,
                toUserId: userId,
                stars: clampedStars,
                comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                date: Date()
            )
        )
        recalculateRating(for: userId)
    }

    func user(by id: UUID) -> AppUser? {
        users.first(where: { $0.id == id })
    }

    func shift(by id: UUID) -> JobShift? {
        shifts.first(where: { $0.id == id })
    }

    func reviews(for userId: UUID) -> [Review] {
        reviews
            .filter { $0.toUserId == userId }
            .sorted { $0.date > $1.date }
    }

    private func syncShiftCapacity(for shiftId: UUID) {
        guard let shiftIndex = shifts.firstIndex(where: { $0.id == shiftId }) else { return }

        if acceptedApplicationsCount(for: shiftId) >= shifts[shiftIndex].requiredWorkers {
            shifts[shiftIndex].status = .closed

            for idx in applications.indices where applications[idx].shiftId == shiftId && applications[idx].status == .pending {
                applications[idx].status = .rejected
            }
        } else {
            shifts[shiftIndex].status = .open
        }
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
        let employer1 = AppUser(
            id: UUID(),
            name: "Cafe Central",
            email: "cafe@quickgig.app",
            password: "123456",
            role: .employer,
            rating: 0,
            reviewsCount: 0
        )

        let employer2 = AppUser(
            id: UUID(),
            name: "Logistics Hub",
            email: "logistics@quickgig.app",
            password: "123456",
            role: .employer,
            rating: 0,
            reviewsCount: 0
        )

        let worker1 = AppUser(
            id: UUID(),
            name: "Alex Ivanov",
            email: "alex@quickgig.app",
            password: "123456",
            role: .worker,
            rating: 0,
            reviewsCount: 0
        )

        let worker2 = AppUser(
            id: UUID(),
            name: "Nina Petrova",
            email: "nina@quickgig.app",
            password: "123456",
            role: .worker,
            rating: 0,
            reviewsCount: 0
        )

        users = [employer1, employer2, worker1, worker2]

        let calendar = Calendar.current
        let now = Date()
        let start1 = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let end1 = calendar.date(byAdding: .hour, value: 8, to: start1) ?? start1

        let start2 = calendar.date(byAdding: .day, value: 2, to: now) ?? now
        let end2 = calendar.date(byAdding: .hour, value: 6, to: start2) ?? start2

        let start3 = calendar.date(byAdding: .day, value: 3, to: now) ?? now
        let end3 = calendar.date(byAdding: .hour, value: 10, to: start3) ?? start3

        let shift1 = JobShift(
            id: UUID(),
            title: "Бариста на утро",
            details: "Нужна помощь с 08:00 до 16:00, опыт приветствуется",
            pay: 120,
            startDate: start1,
            endDate: end1,
            coordinate: CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234),
            employerId: employer1.id,
            requiredWorkers: 2,
            status: .open
        )

        let shift2 = JobShift(
            id: UUID(),
            title: "Погрузка товара",
            details: "Склад, смена на 6 часов, перерывы включены",
            pay: 140,
            startDate: start2,
            endDate: end2,
            coordinate: CLLocationCoordinate2D(latitude: 49.8397, longitude: 24.0297),
            employerId: employer2.id,
            requiredWorkers: 1,
            status: .open
        )

        let shift3 = JobShift(
            id: UUID(),
            title: "Промо у ТЦ",
            details: "Раздача листовок, коммуникация с клиентами",
            pay: 110,
            startDate: start3,
            endDate: end3,
            coordinate: CLLocationCoordinate2D(latitude: 46.4825, longitude: 30.7233),
            employerId: employer1.id,
            requiredWorkers: 3,
            status: .open
        )

        shifts = [shift1, shift2, shift3]

        reviews = [
            Review(
                id: UUID(),
                fromUserId: worker1.id,
                toUserId: employer1.id,
                stars: 5,
                comment: "Все четко и вовремя оплатили",
                date: now
            ),
            Review(
                id: UUID(),
                fromUserId: employer1.id,
                toUserId: worker1.id,
                stars: 5,
                comment: "Ответственный и пунктуальный",
                date: now
            ),
            Review(
                id: UUID(),
                fromUserId: worker2.id,
                toUserId: employer2.id,
                stars: 4,
                comment: "Задача понятная, но много физической нагрузки",
                date: now
            )
        ]

        recalculateRating(for: employer1.id)
        recalculateRating(for: employer2.id)
        recalculateRating(for: worker1.id)
        recalculateRating(for: worker2.id)

        applications = [
            ShiftApplication(
                id: UUID(),
                shiftId: shift1.id,
                workerId: worker1.id,
                status: .accepted,
                createdAt: now
            ),
            ShiftApplication(
                id: UUID(),
                shiftId: shift2.id,
                workerId: worker2.id,
                status: .pending,
                createdAt: now
            )
        ]

        syncShiftCapacity(for: shift1.id)
        syncShiftCapacity(for: shift2.id)
        syncShiftCapacity(for: shift3.id)
    }
}
