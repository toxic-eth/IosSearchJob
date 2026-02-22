import Foundation
import Combine
import CoreLocation

enum EmailVerificationStep {
    case none
    case confirmFirstEmail
    case verifyOldEmail
    case enterNewEmail
    case verifyNewEmail
}

final class AppState: ObservableObject {
    private let employerResponseSLAHours = 2
    private let reminderCooldownMinutes = 20
    private let criticalSLAMinutes = 30
    private let usersStorageKey = "quickgig.users.v1"
    private let currentUserIdStorageKey = "quickgig.currentUserId.v1"
    private let verificationCooldownSeconds = 60
    private var slaTimerCancellable: AnyCancellable?
    private var reminderTimestamps: [UUID: Date] = [:]
    private var activePhoneVerificationCode: String?
    private let demoShiftTargetCount = 50
    private let demoCityCoordinates: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234), // Київ
        CLLocationCoordinate2D(latitude: 49.8397, longitude: 24.0297), // Львів
        CLLocationCoordinate2D(latitude: 46.4825, longitude: 30.7233), // Одеса
        CLLocationCoordinate2D(latitude: 48.4647, longitude: 35.0462), // Дніпро
        CLLocationCoordinate2D(latitude: 49.9935, longitude: 36.2304)  // Харків
    ]

    @Published var currentUser: AppUser?
    @Published var users: [AppUser] = []
    @Published var shifts: [JobShift] = []
    @Published var reviews: [Review] = []
    @Published var applications: [ShiftApplication] = []
    @Published var notifications: [InAppNotification] = []
    @Published var authErrorMessage: String?
    @Published private(set) var shouldRequestLocationPermission = false
    @Published private(set) var phoneVerificationMaskedPhone = ""
    @Published private(set) var phoneVerificationDemoCode = ""
    @Published private(set) var phoneVerificationResendAvailableAt = Date()
    @Published private(set) var emailVerificationStep: EmailVerificationStep = .none
    @Published private(set) var emailVerificationDemoCode = ""

    init() {
        if !loadPersistedAuthState() {
            seedData()
            persistAuthState()
        }
        ensureDemoMarketplaceData()
        NotificationService.requestAuthorizationIfNeeded()
        startSLATimer()
    }

    var isLoggedIn: Bool {
        currentUser != nil
    }

    var requiresPhoneVerification: Bool {
        guard let currentUser else { return false }
        return !currentUser.isPhoneVerified
    }

    func currentUserNotifications() -> [InAppNotification] {
        guard let currentUser else { return [] }
        return notifications
            .filter { $0.userId == currentUser.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func unreadNotificationsCountForCurrentUser() -> Int {
        currentUserNotifications().filter { !$0.isRead }.count
    }

    func markNotificationAsRead(_ notificationId: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == notificationId }) else { return }
        notifications[index].isRead = true
    }

    func markAllNotificationsAsReadForCurrentUser() {
        guard let currentUser else { return }
        for index in notifications.indices where notifications[index].userId == currentUser.id {
            notifications[index].isRead = true
        }
    }

    func consumeLocationPermissionRequest() -> Bool {
        guard shouldRequestLocationPermission else { return false }
        shouldRequestLocationPermission = false
        return true
    }

    func register(name: String, phone: String, password: String, role: UserRole) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPhone = normalizePhone(phone)

        guard !normalizedName.isEmpty else {
            authErrorMessage = "Введіть ім'я або назву компанії"
            return false
        }

        guard isValidPhone(normalizedPhone) else {
            authErrorMessage = "Номер має починатися з 380 і містити 12 цифр"
            return false
        }

        guard password.count >= 6 else {
            authErrorMessage = "Пароль має містити щонайменше 6 символів"
            return false
        }

        if users.contains(where: { $0.phone == normalizedPhone }) {
            authErrorMessage = "Користувач з таким номером вже існує"
            return false
        }

        let user = AppUser(
            id: UUID(),
            name: normalizedName,
            phone: normalizedPhone,
            isPhoneVerified: false,
            email: "",
            isEmailVerified: false,
            password: password,
            role: role,
            resumeSummary: "",
            isVerifiedEmployer: false,
            rating: 0,
            reviewsCount: 0
        )

        users.append(user)
        currentUser = user
        shouldRequestLocationPermission = true
        authErrorMessage = nil
        beginPhoneVerificationIfNeeded()
        persistAuthState()
        return true
    }

    func login(phone: String, password: String, expectedRole: UserRole? = nil) -> Bool {
        let normalizedPhone = normalizePhone(phone)
        guard isValidPhone(normalizedPhone) else {
            authErrorMessage = "Номер має починатися з 380 і містити 12 цифр"
            return false
        }

        guard let user = users.first(where: { $0.phone == normalizedPhone }) else {
            authErrorMessage = "Користувача не знайдено"
            return false
        }

        guard user.password == password else {
            authErrorMessage = "Неправильний пароль"
            return false
        }

        if let expectedRole, user.role != expectedRole {
            authErrorMessage = expectedRole == .worker
                ? "Цей акаунт зареєстровано як роботодавець"
                : "Цей акаунт зареєстровано як працівник"
            return false
        }

        currentUser = user
        shouldRequestLocationPermission = false
        authErrorMessage = nil
        beginPhoneVerificationIfNeeded()
        persistAuthState()
        return true
    }

    func updateCurrentUserEmail(_ email: String) -> Bool {
        guard let currentUser else { return false }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !normalized.isEmpty && !isValidEmail(normalized) {
            authErrorMessage = "Введіть коректний email"
            return false
        }

        guard let index = users.firstIndex(where: { $0.id == currentUser.id }) else { return false }
        users[index].email = normalized
        self.currentUser = users[index]
        authErrorMessage = nil
        persistAuthState()
        return true
    }

    func startFirstEmailVerification(email: String) -> Bool {
        guard let currentUser else { return false }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(normalized) else {
            authErrorMessage = "Введіть коректний email"
            return false
        }

        guard let index = users.firstIndex(where: { $0.id == currentUser.id }) else { return false }
        users[index].email = normalized
        users[index].isEmailVerified = false
        self.currentUser = users[index]
        emailVerificationStep = .confirmFirstEmail
        emailVerificationDemoCode = generate4DigitCode()
        authErrorMessage = nil
        persistAuthState()
        return true
    }

    func confirmFirstEmail(code: String) -> Bool {
        guard emailVerificationStep == .confirmFirstEmail else { return false }
        guard code.trimmingCharacters(in: .whitespacesAndNewlines) == emailVerificationDemoCode else {
            authErrorMessage = "Невірний код підтвердження"
            return false
        }
        guard let currentUser, let index = users.firstIndex(where: { $0.id == currentUser.id }) else { return false }
        users[index].isEmailVerified = true
        self.currentUser = users[index]
        emailVerificationStep = .none
        emailVerificationDemoCode = ""
        authErrorMessage = nil
        persistAuthState()
        return true
    }

    func beginEmailChange() {
        guard let currentUser, currentUser.isEmailVerified, !currentUser.email.isEmpty else { return }
        emailVerificationStep = .verifyOldEmail
        emailVerificationDemoCode = generate4DigitCode()
        authErrorMessage = nil
    }

    func confirmOldEmailForChange(code: String) -> Bool {
        guard emailVerificationStep == .verifyOldEmail else { return false }
        guard code.trimmingCharacters(in: .whitespacesAndNewlines) == emailVerificationDemoCode else {
            authErrorMessage = "Невірний код зі старої пошти"
            return false
        }
        emailVerificationStep = .enterNewEmail
        emailVerificationDemoCode = ""
        authErrorMessage = nil
        return true
    }

    func submitNewEmailForChange(_ email: String) -> Bool {
        guard emailVerificationStep == .enterNewEmail else { return false }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(normalized) else {
            authErrorMessage = "Введіть коректний email"
            return false
        }
        guard let currentUser, let index = users.firstIndex(where: { $0.id == currentUser.id }) else { return false }
        users[index].email = normalized
        users[index].isEmailVerified = false
        self.currentUser = users[index]
        emailVerificationStep = .verifyNewEmail
        emailVerificationDemoCode = generate4DigitCode()
        authErrorMessage = nil
        persistAuthState()
        return true
    }

    func confirmNewEmailForChange(code: String) -> Bool {
        guard emailVerificationStep == .verifyNewEmail else { return false }
        guard code.trimmingCharacters(in: .whitespacesAndNewlines) == emailVerificationDemoCode else {
            authErrorMessage = "Невірний код з нової пошти"
            return false
        }
        guard let currentUser, let index = users.firstIndex(where: { $0.id == currentUser.id }) else { return false }
        users[index].isEmailVerified = true
        self.currentUser = users[index]
        emailVerificationStep = .none
        emailVerificationDemoCode = ""
        authErrorMessage = nil
        persistAuthState()
        return true
    }

    func ensurePhoneVerificationSession() {
        beginPhoneVerificationIfNeeded()
    }

    func phoneVerificationSecondsRemaining(now: Date = Date()) -> Int {
        max(0, Int(phoneVerificationResendAvailableAt.timeIntervalSince(now)))
    }

    @discardableResult
    func resendPhoneVerificationCode(now: Date = Date()) -> Bool {
        guard requiresPhoneVerification else { return false }
        guard phoneVerificationSecondsRemaining(now: now) == 0 else { return false }

        generatePhoneVerificationCode(now: now)
        return true
    }

    func submitPhoneVerification(code: String) -> Bool {
        guard let currentUser, requiresPhoneVerification else { return true }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized == activePhoneVerificationCode else {
            authErrorMessage = "Невірний код підтвердження"
            return false
        }

        guard let index = users.firstIndex(where: { $0.id == currentUser.id }) else { return false }
        users[index].isPhoneVerified = true
        self.currentUser = users[index]
        authErrorMessage = nil
        resetPhoneVerificationSession()
        persistAuthState()
        return true
    }

    func logout() {
        currentUser = nil
        shouldRequestLocationPermission = false
        resetPhoneVerificationSession()
        persistAuthState()
    }

    func addShift(title: String, details: String, pay: Int, startDate: Date, endDate: Date, coordinate: CLLocationCoordinate2D, workFormat: WorkFormat, requiredWorkers: Int) {
        guard let currentUser, currentUser.role == .employer else { return }
        let finalCoordinate = UkraineRegion.contains(coordinate) ? coordinate : UkraineRegion.center
        let cityName = cityNameForCoordinate(finalCoordinate)
        let autoAddress = "м. \(cityName), локація на мапі"

        shifts.append(
            JobShift(
                id: UUID(),
                title: title,
                details: details,
                address: autoAddress,
                pay: pay,
                startDate: startDate,
                endDate: endDate,
                coordinate: finalCoordinate,
                employerId: currentUser.id,
                workFormat: workFormat,
                requiredWorkers: max(1, requiredWorkers),
                status: .open
            )
        )
    }

    func apply(to shiftId: UUID) {
        guard let currentUser, currentUser.role == .worker else { return }
        guard let shift = shift(by: shiftId), shift.status == .open, !isShiftFull(shift) else { return }
        guard !applications.contains(where: { $0.shiftId == shiftId && $0.workerId == currentUser.id }) else { return }

        let createdAt = Date()
        applications.append(
            ShiftApplication(
                id: UUID(),
                shiftId: shiftId,
                workerId: currentUser.id,
                status: .pending,
                createdAt: createdAt,
                respondBy: Calendar.current.date(byAdding: .hour, value: employerResponseSLAHours, to: createdAt) ?? createdAt
            )
        )

        addInAppNotification(
            for: currentUser.id,
            title: "Відгук надіслано",
            message: "Очікуйте рішення роботодавця по зміні «\(shift.title)».",
            kind: .info
        )

        addInAppNotification(
            for: shift.employerId,
            title: "Новий кандидат",
            message: "\(currentUser.name) відгукнувся на зміну «\(shift.title)».",
            kind: .warning
        )
    }

    func updateApplicationStatus(applicationId: UUID, status: ApplicationStatus) {
        guard let index = applications.firstIndex(where: { $0.id == applicationId }) else { return }
        let oldStatus = applications[index].status

        let shiftId = applications[index].shiftId
        if status == .accepted,
           let shift = shift(by: shiftId),
           acceptedApplicationsCount(for: shift.id) >= shift.requiredWorkers,
           applications[index].status != .accepted {
            return
        }

        applications[index].status = status
        if status != .pending {
            reminderTimestamps[applications[index].id] = nil
        }
        if oldStatus != status {
            notifyStatusChangeIfNeeded(for: applications[index])
        }
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

    func applicationTimeRemainingText(_ application: ShiftApplication, now: Date = Date()) -> String {
        guard application.status == .pending else { return application.status.title }

        let remaining = Int(application.respondBy.timeIntervalSince(now))
        if remaining <= 0 {
            return "Термін відповіді сплив"
        }

        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return "Відповідь до: \(hours) год \(minutes) хв"
        }
        return "Відповідь до: \(minutes) хв"
    }

    func isApplicationSLACritical(_ application: ShiftApplication, now: Date = Date()) -> Bool {
        guard application.status == .pending else { return false }
        let minutesLeft = application.respondBy.timeIntervalSince(now) / 60
        return minutesLeft > 0 && minutesLeft <= Double(criticalSLAMinutes)
    }

    func canSendReminder(for application: ShiftApplication, now: Date = Date()) -> Bool {
        guard application.status == .pending else { return false }
        guard let lastSentAt = reminderTimestamps[application.id] else { return true }
        return now.timeIntervalSince(lastSentAt) >= Double(reminderCooldownMinutes * 60)
    }

    func reminderCooldownText(for application: ShiftApplication, now: Date = Date()) -> String? {
        guard !canSendReminder(for: application, now: now),
              let lastSentAt = reminderTimestamps[application.id] else { return nil }

        let remaining = Int(Double(reminderCooldownMinutes * 60) - now.timeIntervalSince(lastSentAt))
        if remaining <= 0 { return nil }
        let minutes = max(1, remaining / 60)
        return "Повторне нагадування через \(minutes) хв"
    }

    func remindEmployer(for applicationId: UUID) {
        guard let application = applications.first(where: { $0.id == applicationId }),
              let worker = currentUser,
              worker.role == .worker,
              worker.id == application.workerId,
              application.status == .pending,
              canSendReminder(for: application),
              let shift = shift(by: application.shiftId) else { return }

        reminderTimestamps[application.id] = Date()

        addInAppNotification(
            for: shift.employerId,
            title: "Нагадування від кандидата",
            message: "\(worker.name) просить пришвидшити рішення по зміні «\(shift.title)».",
            kind: .warning
        )

        addInAppNotification(
            for: worker.id,
            title: "Нагадування надіслано",
            message: "Роботодавець отримав нагадування по зміні «\(shift.title)».",
            kind: .success
        )
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

    func updateCurrentUserResume(_ text: String) {
        guard let currentUser else { return }
        guard let index = users.firstIndex(where: { $0.id == currentUser.id }) else { return }

        users[index].resumeSummary = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentUser = users[index]
        persistAuthState()
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
                reminderTimestamps[applications[idx].id] = nil
                notifyStatusChangeIfNeeded(for: applications[idx])
            }
        } else {
            shifts[shiftIndex].status = .open
        }
    }

    private func startSLATimer() {
        slaTimerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.expireOverdueApplications()
            }
    }

    private func expireOverdueApplications(now: Date = Date()) {
        var changedShiftIds: Set<UUID> = []

        for index in applications.indices where applications[index].status == .pending {
            if applications[index].respondBy < now {
                applications[index].status = .rejected
                reminderTimestamps[applications[index].id] = nil
                notifyStatusChangeIfNeeded(for: applications[index])
                changedShiftIds.insert(applications[index].shiftId)
            }
        }

        for shiftId in changedShiftIds {
            syncShiftCapacity(for: shiftId)
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

    private func addInAppNotification(for userId: UUID, title: String, message: String, kind: NotificationKind) {
        notifications.append(
            InAppNotification(
                id: UUID(),
                userId: userId,
                title: title,
                message: message,
                kind: kind,
                createdAt: Date(),
                isRead: false
            )
        )
    }

    private func normalizePhone(_ phone: String) -> String {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.decimalDigits
        let digits = trimmed.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(digits))
    }

    private func isValidPhone(_ phone: String) -> Bool {
        phone.count == 12 && phone.hasPrefix("380") && phone.allSatisfy(\.isNumber)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: regex, options: .regularExpression) != nil
    }

    private func generate4DigitCode() -> String {
        String(Int.random(in: 1000...9999))
    }

    private func beginPhoneVerificationIfNeeded() {
        guard requiresPhoneVerification, let currentUser else {
            resetPhoneVerificationSession()
            return
        }

        phoneVerificationMaskedPhone = maskPhone(currentUser.phone)
        if activePhoneVerificationCode == nil {
            generatePhoneVerificationCode(now: Date())
        }
    }

    private func generatePhoneVerificationCode(now: Date) {
        let code = Int.random(in: 1000...9999)
        activePhoneVerificationCode = String(code)
        phoneVerificationDemoCode = String(code)
        phoneVerificationResendAvailableAt = now.addingTimeInterval(TimeInterval(verificationCooldownSeconds))
    }

    private func resetPhoneVerificationSession() {
        activePhoneVerificationCode = nil
        phoneVerificationDemoCode = ""
        phoneVerificationMaskedPhone = ""
        phoneVerificationResendAvailableAt = Date()
    }

    private func maskPhone(_ phone: String) -> String {
        guard phone.count > 4 else { return phone }
        let suffix = phone.suffix(4)
        return "••••••\(suffix)"
    }

    private struct PersistedUser: Codable {
        let id: UUID
        let name: String
        let phone: String
        let isPhoneVerified: Bool
        let email: String
        let isEmailVerified: Bool
        let password: String
        let role: String
        let resumeSummary: String
        let isVerifiedEmployer: Bool
        let rating: Double
        let reviewsCount: Int
    }

    private func persistAuthState() {
        let payload = users.map {
            PersistedUser(
                id: $0.id,
                name: $0.name,
                phone: $0.phone,
                isPhoneVerified: $0.isPhoneVerified,
                email: $0.email,
                isEmailVerified: $0.isEmailVerified,
                password: $0.password,
                role: $0.role.rawValue,
                resumeSummary: $0.resumeSummary,
                isVerifiedEmployer: $0.isVerifiedEmployer,
                rating: $0.rating,
                reviewsCount: $0.reviewsCount
            )
        }

        if let encoded = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(encoded, forKey: usersStorageKey)
        }
        UserDefaults.standard.set(currentUser?.id.uuidString, forKey: currentUserIdStorageKey)
    }

    private func loadPersistedAuthState() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: usersStorageKey),
              let payload = try? JSONDecoder().decode([PersistedUser].self, from: data),
              !payload.isEmpty else { return false }

        let restoredUsers: [AppUser] = payload.compactMap { item in
            guard let role = UserRole(rawValue: item.role) else { return nil }
            return AppUser(
                id: item.id,
                name: item.name,
                phone: item.phone,
                isPhoneVerified: item.isPhoneVerified,
                email: item.email,
                isEmailVerified: item.isEmailVerified,
                password: item.password,
                role: role,
                resumeSummary: item.resumeSummary,
                isVerifiedEmployer: item.isVerifiedEmployer,
                rating: item.rating,
                reviewsCount: item.reviewsCount
            )
        }
        guard !restoredUsers.isEmpty else { return false }

        users = restoredUsers

        if let idRaw = UserDefaults.standard.string(forKey: currentUserIdStorageKey),
           let id = UUID(uuidString: idRaw),
           let found = restoredUsers.first(where: { $0.id == id }) {
            currentUser = found
            beginPhoneVerificationIfNeeded()
        } else {
            currentUser = nil
            resetPhoneVerificationSession()
        }
        return true
    }

    private func notifyStatusChangeIfNeeded(for application: ShiftApplication) {
        guard application.status != .pending,
              let shift = shift(by: application.shiftId) else { return }

        NotificationService.notifyApplicationStatusChange(
            shiftTitle: shift.title,
            status: application.status
        )

        addInAppNotification(
            for: application.workerId,
            title: "Статус відгуку змінено",
            message: "Зміна «\(shift.title)»: \(application.status.title.lowercased()).",
            kind: application.status == .accepted ? .success : .error
        )

        if let worker = user(by: application.workerId) {
            addInAppNotification(
                for: shift.employerId,
                title: "Оновлення по кандидату",
                message: "Кандидат \(worker.name): \(application.status.title.lowercased()) на зміну «\(shift.title)».",
                kind: .info
            )
        }
    }

    private func ensureDemoMarketplaceData() {
        if shifts.count >= demoShiftTargetCount { return }
        guard users.filter({ $0.role == .employer }).count >= 2,
              users.filter({ $0.role == .worker }).count >= 2 else { return }

        let employers = users.filter { $0.role == .employer }
        let workers = users.filter { $0.role == .worker }
        let employer1 = employers[0]
        let employer2 = employers[1]
        let worker1 = workers[0]
        let worker2 = workers[1]

        let now = Date()
        shifts = buildDemoShifts(employer1: employer1, employer2: employer2, now: now)

        reviews = [
            Review(id: UUID(), fromUserId: worker1.id, toUserId: employer1.id, stars: 5, comment: "Усе чітко, оплатили вчасно", date: now),
            Review(id: UUID(), fromUserId: employer1.id, toUserId: worker1.id, stars: 5, comment: "Відповідальний і пунктуальний", date: now),
            Review(id: UUID(), fromUserId: worker2.id, toUserId: employer2.id, stars: 4, comment: "Завдання зрозуміле, але багато фізичного навантаження", date: now)
        ]

        recalculateRating(for: employer1.id)
        recalculateRating(for: employer2.id)
        recalculateRating(for: worker1.id)
        recalculateRating(for: worker2.id)

        applications = [
            ShiftApplication(id: UUID(), shiftId: shifts.first?.id ?? UUID(), workerId: worker1.id, status: .accepted, createdAt: now, respondBy: now),
            ShiftApplication(id: UUID(), shiftId: shifts.dropFirst().first?.id ?? UUID(), workerId: worker2.id, status: .pending, createdAt: now, respondBy: Calendar.current.date(byAdding: .hour, value: employerResponseSLAHours, to: now) ?? now)
        ]

        for shift in shifts {
            syncShiftCapacity(for: shift.id)
        }
    }

    private func seedData() {
        let employer1 = AppUser(
            id: UUID(),
            name: "Cafe Central",
            phone: "380671112233",
            isPhoneVerified: true,
            email: "cafe@quickgig.app",
            isEmailVerified: true,
            password: "123456",
            role: .employer,
            resumeSummary: "",
            isVerifiedEmployer: true,
            rating: 0,
            reviewsCount: 0
        )

        let employer2 = AppUser(
            id: UUID(),
            name: "Logistics Hub",
            phone: "380672223344",
            isPhoneVerified: true,
            email: "logistics@quickgig.app",
            isEmailVerified: true,
            password: "123456",
            role: .employer,
            resumeSummary: "",
            isVerifiedEmployer: false,
            rating: 0,
            reviewsCount: 0
        )

        let worker1 = AppUser(
            id: UUID(),
            name: "Alex Ivanov",
            phone: "380673334455",
            isPhoneVerified: true,
            email: "alex@quickgig.app",
            isEmailVerified: true,
            password: "123456",
            role: .worker,
            resumeSummary: "Бариста, каса, робота з гостями.",
            isVerifiedEmployer: false,
            rating: 0,
            reviewsCount: 0
        )

        let worker2 = AppUser(
            id: UUID(),
            name: "Nina Petrova",
            phone: "380674445566",
            isPhoneVerified: true,
            email: "nina@quickgig.app",
            isEmailVerified: true,
            password: "123456",
            role: .worker,
            resumeSummary: "Складські роботи, пакування, інвентаризація.",
            isVerifiedEmployer: false,
            rating: 0,
            reviewsCount: 0
        )

        users = [employer1, employer2, worker1, worker2]

        let now = Date()
        shifts = buildDemoShifts(employer1: employer1, employer2: employer2, now: now)

        reviews = [
            Review(
                id: UUID(),
                fromUserId: worker1.id,
                toUserId: employer1.id,
                stars: 5,
                comment: "Усе чітко, оплатили вчасно",
                date: now
            ),
            Review(
                id: UUID(),
                fromUserId: employer1.id,
                toUserId: worker1.id,
                stars: 5,
                comment: "Відповідальний і пунктуальний",
                date: now
            ),
            Review(
                id: UUID(),
                fromUserId: worker2.id,
                toUserId: employer2.id,
                stars: 4,
                comment: "Завдання зрозуміле, але багато фізичного навантаження",
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
                shiftId: shifts.first?.id ?? UUID(),
                workerId: worker1.id,
                status: .accepted,
                createdAt: now,
                respondBy: now
            ),
            ShiftApplication(
                id: UUID(),
                shiftId: shifts.dropFirst().first?.id ?? UUID(),
                workerId: worker2.id,
                status: .pending,
                createdAt: now,
                respondBy: Calendar.current.date(byAdding: .hour, value: employerResponseSLAHours, to: now) ?? now
            )
        ]

        for shift in shifts {
            syncShiftCapacity(for: shift.id)
        }
    }

    private func buildDemoShifts(employer1: AppUser, employer2: AppUser, now: Date) -> [JobShift] {
        let calendar = Calendar.current
        let cityNames = ["Київ", "Львів", "Одеса", "Дніпро", "Харків"]
        let cityStreets: [[String]] = [
            ["Хрещатик", "Саксаганського", "Велика Васильківська", "Антоновича", "Жилянська", "Глибочицька"],
            ["Городоцька", "Кульпарківська", "Стрийська", "Наукова", "Зелена", "Личаківська"],
            ["Дерибасівська", "Рішельєвська", "Пантелеймонівська", "Фонтанська дорога", "Середньофонтанська", "Преображенська"],
            ["Яворницького", "Набережна Перемоги", "Січеславська Набережна", "Робоча", "Титова", "Калнишевського"],
            ["Сумська", "Пушкінська", "Полтавський Шлях", "Науки", "Клочківська", "Героїв Праці"]
        ]
        let templates: [(String, String, Int, Int, Int, WorkFormat, Int, Int, Int)] = [
            ("Бариста на ранок", "Підготовка кави, каса, ранковий потік гостей", 180, 1, 6, .offline, 2, 8, 0),
            ("Комплектувальник складу", "Збір замовлень зі сканером та упаковка", 190, 1, 8, .offline, 4, 9, 30),
            ("Промоутер біля ТЦ", "Комунікація з клієнтами та роздача флаєрів", 165, 2, 5, .offline, 3, 12, 0),
            ("Оператор чату", "Відповіді у чаті підтримки за готовим скриптом", 175, 2, 7, .online, 2, 10, 0),
            ("Кур'єр по району", "Доставка дрібних замовлень в межах міста", 215, 3, 6, .offline, 5, 11, 0),
            ("Асистент HR", "Первинний скринінг анкет та дзвінки кандидатам", 185, 3, 8, .online, 1, 9, 0),
            ("Фасувальник продукції", "Фасування, маркування та контроль ваги", 178, 4, 7, .offline, 3, 14, 0),
            ("Контент-менеджер", "Оновлення карток товарів і описів", 200, 4, 6, .online, 1, 13, 30),
            ("Адміністратор залу", "Координація персоналу та сервісу в залі", 225, 5, 9, .offline, 2, 15, 0),
            ("Сапорт e-commerce", "Робота з CRM, обробка звернень клієнтів", 195, 5, 8, .online, 2, 16, 0),
            ("Мерчендайзер", "Викладка товару і перевірка цінників", 182, 6, 6, .offline, 3, 8, 30),
            ("Інвентаризація складу", "Перерахунок залишків і звірка по системі", 205, 6, 10, .offline, 6, 20, 0)
        ]

        var demoShifts: [JobShift] = []

        for (cityIndex, city) in demoCityCoordinates.enumerated() {
            for (templateIndex, template) in templates.enumerated() {
                let startBase = calendar.date(byAdding: .day, value: template.3 + cityIndex, to: now) ?? now
                let startDate = calendar.date(bySettingHour: template.7, minute: template.8, second: 0, of: startBase) ?? startBase
                let endDate = calendar.date(byAdding: .hour, value: template.4, to: startDate) ?? startDate

                let latJitter = Double((templateIndex % 5) - 2) * 0.005
                let lonJitter = Double((templateIndex % 4) - 1) * 0.006
                let coordinate = CLLocationCoordinate2D(
                    latitude: city.latitude + latJitter,
                    longitude: city.longitude + lonJitter
                )
                let street = cityStreets[cityIndex][templateIndex % cityStreets[cityIndex].count]
                let house = 10 + (templateIndex * 3) + cityIndex
                let address = "м. \(cityNames[cityIndex]), вул. \(street), \(house)"

                demoShifts.append(
                    JobShift(
                        id: UUID(),
                        title: template.0,
                        details: template.1,
                        address: address,
                        pay: template.2,
                        startDate: startDate,
                        endDate: endDate,
                        coordinate: coordinate,
                        employerId: (templateIndex + cityIndex).isMultiple(of: 2) ? employer1.id : employer2.id,
                        workFormat: template.5,
                        requiredWorkers: template.6,
                        status: .open
                    )
                )
            }
        }

        return demoShifts
    }

    private func cityNameForCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        let cities: [(String, CLLocationCoordinate2D)] = [
            ("Київ", CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234)),
            ("Львів", CLLocationCoordinate2D(latitude: 49.8397, longitude: 24.0297)),
            ("Одеса", CLLocationCoordinate2D(latitude: 46.4825, longitude: 30.7233)),
            ("Дніпро", CLLocationCoordinate2D(latitude: 48.4647, longitude: 35.0462)),
            ("Харків", CLLocationCoordinate2D(latitude: 49.9935, longitude: 36.2304))
        ]

        let point = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearest = cities.min { lhs, rhs in
            let lDist = point.distance(from: CLLocation(latitude: lhs.1.latitude, longitude: lhs.1.longitude))
            let rDist = point.distance(from: CLLocation(latitude: rhs.1.latitude, longitude: rhs.1.longitude))
            return lDist < rDist
        }
        return nearest?.0 ?? "Київ"
    }
}
