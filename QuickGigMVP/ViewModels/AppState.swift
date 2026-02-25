import Foundation
import Combine
import CoreLocation

enum EmailVerificationStep {
    case none
    case confirmFirstEmail
    case enterChangeEmails
    case verifyOldEmail
    case verifyNewEmail
}

final class AppState: ObservableObject {
    private let employerResponseSLAHours = 2
    private let reminderCooldownMinutes = 20
    private let criticalSLAMinutes = 30
    private let disputeSLAOpenMinutes = 30
    private let disputeAutoResolutionHours = 24
    private let notificationDedupSeconds = 90
    private let noShowCooldownHours = 24
    private let workerServiceFeeRate = 0.12
    private let employerServiceFeeRate = 0.10
    private let employerInitialDemoBalance = 120_000
    private let usersStorageKey = "quickgig.users.v1"
    private let currentUserIdStorageKey = "quickgig.currentUserId.v1"
    private let walletBalancesStorageKey = "quickgig.wallets.v1"
    private let walletTransactionsStorageKey = "quickgig.wallet.tx.v1"
    private let moderationCasesStorageKey = "quickgig.moderation.cases.v1"
    private let moderationActionsStorageKey = "quickgig.moderation.actions.v1"
    private let auditEventsStorageKey = "quickgig.audit.events.v1"
    private let verificationCooldownSeconds = 60
    private var slaTimerCancellable: AnyCancellable?
    private var reminderTimestamps: [UUID: Date] = [:]
    private var lastNotificationTimestampsByKey: [String: Date] = [:]
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
    @Published var conversations: [ShiftConversation] = []
    @Published var chatMessages: [ChatMessage] = []
    @Published var dealOffers: [DealOffer] = []
    @Published var shiftExecutionEvents: [ShiftExecutionEvent] = []
    @Published var shiftDisputes: [ShiftDispute] = []
    @Published var disputeUpdates: [DisputeUpdate] = []
    @Published var payoutRecords: [PayoutRecord] = []
    @Published var walletBalances: [UUID: Int] = [:]
    @Published var walletTransactions: [WalletTransaction] = []
    @Published var riskSignals: [RiskSignal] = []
    @Published var moderationCases: [ModerationCase] = []
    @Published var moderationActions: [ModerationCaseAction] = []
    @Published var auditEvents: [AuditEvent] = []
    @Published var blockedConversationPairs: Set<String> = []
    @Published var authErrorMessage: String?
    @Published private(set) var shouldRequestLocationPermission = false
    @Published private(set) var phoneVerificationMaskedPhone = ""
    @Published private(set) var phoneVerificationDemoCode = ""
    @Published private(set) var phoneVerificationResendAvailableAt = Date()
    @Published private(set) var emailVerificationStep: EmailVerificationStep = .none
    @Published private(set) var emailVerificationDemoCode = ""
    private var pendingNewEmailForChange = ""

    init() {
        if !loadPersistedAuthState() {
            seedData()
            persistAuthState()
        }
        loadWalletState()
        loadModerationState()
        loadModerationActionsState()
        loadAuditState()
        ensureWalletsForEmployers()
        ensureDemoMarketplaceData()
        ensurePayoutRecordsForAcceptedApplications()
        recalculateReliabilityForAll()
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

    func conversationsForCurrentUser() -> [ShiftConversation] {
        guard let currentUser else { return [] }
        return conversations
            .filter { $0.employerId == currentUser.id || $0.workerId == currentUser.id }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    func conversation(for shiftId: UUID, workerId: UUID) -> ShiftConversation? {
        guard let shift = shift(by: shiftId) else { return nil }
        return conversations.first(where: {
            $0.shiftId == shiftId &&
            $0.workerId == workerId &&
            $0.employerId == shift.employerId
        })
    }

    func ensureConversation(shiftId: UUID, workerId: UUID) -> ShiftConversation? {
        guard let shift = shift(by: shiftId) else { return nil }
        if let existing = conversation(for: shiftId, workerId: workerId) {
            return existing
        }
        let now = Date()
        let created = ShiftConversation(
            id: UUID(),
            shiftId: shiftId,
            employerId: shift.employerId,
            workerId: workerId,
            createdAt: now,
            lastMessageAt: now,
            employerLastReadAt: now,
            workerLastReadAt: now
        )
        conversations.append(created)
        return created
    }

    func messages(for conversationId: UUID) -> [ChatMessage] {
        chatMessages
            .filter { $0.conversationId == conversationId }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func offers(for conversationId: UUID) -> [DealOffer] {
        dealOffers
            .filter { $0.conversationId == conversationId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func unreadChatCountForCurrentUser() -> Int {
        guard let currentUser else { return 0 }
        return conversationsForCurrentUser().reduce(0) { partial, convo in
            let lastRead = convo.employerId == currentUser.id ? convo.employerLastReadAt : convo.workerLastReadAt
            let unread = chatMessages.contains(where: {
                $0.conversationId == convo.id &&
                $0.senderRole == .user &&
                $0.senderId != currentUser.id &&
                $0.createdAt > lastRead
            })
            return partial + (unread ? 1 : 0)
        }
    }

    func unreadMessagesCount(in conversationId: UUID) -> Int {
        guard let currentUser,
              let convo = conversations.first(where: { $0.id == conversationId }) else { return 0 }
        let lastRead = convo.employerId == currentUser.id ? convo.employerLastReadAt : convo.workerLastReadAt
        return chatMessages.filter {
            $0.conversationId == conversationId &&
            $0.senderRole == .user &&
            $0.senderId != currentUser.id &&
            $0.createdAt > lastRead
        }.count
    }

    func lastMessage(in conversationId: UUID) -> ChatMessage? {
        chatMessages
            .filter { $0.conversationId == conversationId }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    func markConversationRead(_ conversationId: UUID) {
        guard let currentUser,
              let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let now = Date()
        if conversations[index].employerId == currentUser.id {
            conversations[index].employerLastReadAt = now
        } else if conversations[index].workerId == currentUser.id {
            conversations[index].workerLastReadAt = now
        }
    }

    func isConversationBlocked(_ conversationId: UUID) -> Bool {
        guard let convo = conversations.first(where: { $0.id == conversationId }) else { return false }
        return blockedConversationPairs.contains(blockKey(userA: convo.employerId, userB: convo.workerId))
    }

    func blockCurrentCounterparty(in conversationId: UUID) {
        guard let currentUser,
              let convoIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let convo = conversations[convoIndex]
        let key = blockKey(userA: convo.employerId, userB: convo.workerId)
        blockedConversationPairs.insert(key)

        let stamp = Date()
        chatMessages.append(
            ChatMessage(
                id: UUID(),
                conversationId: conversationId,
                shiftId: convo.shiftId,
                senderId: nil,
                senderRole: .system,
                text: "Діалог заблоковано. Надсилання повідомлень вимкнено.",
                createdAt: stamp,
                isEdited: false,
                offerId: nil
            )
        )
        conversations[convoIndex].lastMessageAt = stamp

        let otherId = currentUser.id == convo.employerId ? convo.workerId : convo.employerId
        addInAppNotification(
            for: otherId,
            title: "Діалог заблоковано",
            message: "Один із учасників заблокував подальшу комунікацію.",
            kind: .warning
        )
    }

    func reportConversationIssue(_ conversationId: UUID, reason: String) {
        guard let currentUser,
              let convo = conversations.first(where: { $0.id == conversationId }) else { return }
        let otherId = currentUser.id == convo.employerId ? convo.workerId : convo.employerId
        addInAppNotification(
            for: currentUser.id,
            title: "Скаргу надіслано",
            message: "Ми отримали вашу скаргу: \(reason).",
            kind: .info
        )
        addInAppNotification(
            for: otherId,
            title: "Скарга на діалог",
            message: "По діалогу створено звернення до підтримки.",
            kind: .warning
        )
    }

    @discardableResult
    func sendMessage(conversationId: UUID, text: String) -> Bool {
        guard let currentUser,
              let convoIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return false }
        let convo = conversations[convoIndex]
        guard convo.employerId == currentUser.id || convo.workerId == currentUser.id else { return false }
        guard !isConversationBlocked(conversationId) else {
            authErrorMessage = "Діалог заблоковано"
            return false
        }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        guard normalized.count <= 1200 else {
            authErrorMessage = "Повідомлення занадто довге"
            return false
        }

        let now = Date()
        analyzeMessageRisk(senderId: currentUser.id, text: normalized, at: now)
        chatMessages.append(
            ChatMessage(
                id: UUID(),
                conversationId: conversationId,
                shiftId: convo.shiftId,
                senderId: currentUser.id,
                senderRole: .user,
                text: normalized,
                createdAt: now,
                isEdited: false,
                offerId: nil
            )
        )
        conversations[convoIndex].lastMessageAt = now
        if convo.employerId == currentUser.id {
            conversations[convoIndex].employerLastReadAt = now
        } else {
            conversations[convoIndex].workerLastReadAt = now
        }

        let recipientId = convo.employerId == currentUser.id ? convo.workerId : convo.employerId
        addInAppNotification(
            for: recipientId,
            title: "Нове повідомлення",
            message: "У вас нове повідомлення по співпраці.",
            kind: .info
        )
        authErrorMessage = nil
        return true
    }

    @discardableResult
    func sendOffer(
        conversationId: UUID,
        payPerHour: Int,
        startDate: Date,
        endDate: Date,
        address: String,
        workersCount: Int
    ) -> Bool {
        guard let currentUser,
              let convoIndex = conversations.firstIndex(where: { $0.id == conversationId }) else { return false }
        let convo = conversations[convoIndex]
        guard convo.employerId == currentUser.id || convo.workerId == currentUser.id else { return false }
        guard !isConversationBlocked(conversationId) else {
            authErrorMessage = "Діалог заблоковано"
            return false
        }

        guard payPerHour >= 1 else {
            authErrorMessage = "Сума офферу має бути більше 0"
            return false
        }
        guard endDate > startDate else {
            authErrorMessage = "Час завершення має бути пізніше старту"
            return false
        }

        let targetId = convo.employerId == currentUser.id ? convo.workerId : convo.employerId
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = Date()

        let offer = DealOffer(
            id: UUID(),
            shiftId: convo.shiftId,
            conversationId: conversationId,
            fromUserId: currentUser.id,
            toUserId: targetId,
            proposedPayPerHour: payPerHour,
            proposedStartDate: startDate,
            proposedEndDate: endDate,
            proposedAddress: normalizedAddress.isEmpty ? "Адреса уточнюється" : normalizedAddress,
            proposedWorkersCount: max(1, workersCount),
            status: .pending,
            createdAt: createdAt,
            respondedAt: nil
        )
        dealOffers.append(offer)

        chatMessages.append(
            ChatMessage(
                id: UUID(),
                conversationId: conversationId,
                shiftId: convo.shiftId,
                senderId: currentUser.id,
                senderRole: .user,
                text: "Надіслано оффер: \(payPerHour) грн/год, \(offer.proposedWorkersCount) працівн.",
                createdAt: createdAt,
                isEdited: false,
                offerId: offer.id
            )
        )

        conversations[convoIndex].lastMessageAt = createdAt
        if convo.employerId == currentUser.id {
            conversations[convoIndex].employerLastReadAt = createdAt
        } else {
            conversations[convoIndex].workerLastReadAt = createdAt
        }

        addInAppNotification(
            for: targetId,
            title: "Новий оффер",
            message: "Ви отримали оффер по співпраці.",
            kind: .warning
        )
        authErrorMessage = nil
        return true
    }

    @discardableResult
    func respondToOffer(offerId: UUID, accept: Bool) -> Bool {
        guard let currentUser,
              let offerIndex = dealOffers.firstIndex(where: { $0.id == offerId }),
              dealOffers[offerIndex].status == .pending else { return false }

        let offer = dealOffers[offerIndex]
        guard offer.toUserId == currentUser.id else { return false }
        guard let convoIndex = conversations.firstIndex(where: { $0.id == offer.conversationId }) else { return false }

        dealOffers[offerIndex].status = accept ? .accepted : .rejected
        dealOffers[offerIndex].respondedAt = Date()

        let statusText = accept ? "Оффер прийнято" : "Оффер відхилено"
        chatMessages.append(
            ChatMessage(
                id: UUID(),
                conversationId: offer.conversationId,
                shiftId: offer.shiftId,
                senderId: currentUser.id,
                senderRole: .user,
                text: statusText,
                createdAt: Date(),
                isEdited: false,
                offerId: offer.id
            )
        )

        if accept {
            applyAcceptedOffer(offer: dealOffers[offerIndex], responderId: currentUser.id)
        }

        conversations[convoIndex].lastMessageAt = Date()
        if conversations[convoIndex].employerId == currentUser.id {
            conversations[convoIndex].employerLastReadAt = Date()
        } else {
            conversations[convoIndex].workerLastReadAt = Date()
        }

        let recipientId = offer.fromUserId
        addInAppNotification(
            for: recipientId,
            title: "Відповідь на оффер",
            message: accept ? "Ваш оффер прийнято." : "Ваш оффер відхилено.",
            kind: accept ? .success : .error
        )
        return true
    }

    private func blockKey(userA: UUID, userB: UUID) -> String {
        let left = userA.uuidString
        let right = userB.uuidString
        return left < right ? "\(left)|\(right)" : "\(right)|\(left)"
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
            reviewsCount: 0,
            reliabilityScore: 0,
            completionRate: 0,
            cancelRate: 0,
            noShowRate: 0,
            employerKYCStatus: .notSubmitted,
            employerCompanyName: "",
            employerTaxId: "",
            kycReviewNote: ""
        )

        users.append(user)
        if role == .employer {
            walletBalances[user.id] = employerInitialDemoBalance
            recordWalletTransaction(
                employerId: user.id,
                payoutRecordId: nil,
                applicationId: nil,
                type: .topUp,
                amount: employerInitialDemoBalance,
                note: "Стартовий баланс нового роботодавця"
            )
            persistWalletState()
        }
        currentUser = user
        recordAuditEvent(
            userId: user.id,
            actorUserId: user.id,
            type: .auth,
            title: "Registration",
            message: "Створено акаунт (\(role.title))",
            relatedId: user.id
        )
        shouldRequestLocationPermission = true
        authErrorMessage = nil
        beginPhoneVerificationIfNeeded()
        persistAuthState()
        persistAuditState()
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
        recordAuditEvent(
            userId: user.id,
            actorUserId: user.id,
            type: .auth,
            title: "Login",
            message: "Успішний вхід",
            relatedId: user.id
        )
        shouldRequestLocationPermission = false
        authErrorMessage = nil
        beginPhoneVerificationIfNeeded()
        persistAuthState()
        persistAuditState()
        return true
    }

    func loginWithApple(expectedRole: UserRole) -> Bool {
        socialSignIn(provider: "apple", displayName: expectedRole == .worker ? "Apple Worker" : "Apple Employer", expectedRole: expectedRole)
    }

    func loginWithGoogle(expectedRole: UserRole) -> Bool {
        socialSignIn(provider: "google", displayName: expectedRole == .worker ? "Google Worker" : "Google Employer", expectedRole: expectedRole)
    }

    private func socialSignIn(provider: String, displayName: String, expectedRole: UserRole) -> Bool {
        if let existing = users.first(where: { $0.email == "\(provider).\(expectedRole.rawValue)@quickgig.app" && $0.role == expectedRole }) {
            currentUser = existing
            recordAuditEvent(
                userId: existing.id,
                actorUserId: existing.id,
                type: .auth,
                title: "Social login",
                message: "Вхід через \(provider)",
                relatedId: existing.id
            )
            shouldRequestLocationPermission = false
            authErrorMessage = nil
            beginPhoneVerificationIfNeeded()
            persistAuthState()
            persistAuditState()
            return true
        }

        let user = AppUser(
            id: UUID(),
            name: displayName,
            phone: generateUniqueDemoPhone(),
            isPhoneVerified: true,
            email: "\(provider).\(expectedRole.rawValue)@quickgig.app",
            isEmailVerified: true,
            password: "",
            role: expectedRole,
            resumeSummary: "",
            isVerifiedEmployer: expectedRole == .employer,
            rating: 0,
            reviewsCount: 0,
            reliabilityScore: 0,
            completionRate: 0,
            cancelRate: 0,
            noShowRate: 0,
            employerKYCStatus: .notSubmitted,
            employerCompanyName: "",
            employerTaxId: "",
            kycReviewNote: ""
        )
        users.append(user)
        if expectedRole == .employer {
            walletBalances[user.id] = employerInitialDemoBalance
            recordWalletTransaction(
                employerId: user.id,
                payoutRecordId: nil,
                applicationId: nil,
                type: .topUp,
                amount: employerInitialDemoBalance,
                note: "Стартовий баланс social-роботодавця"
            )
            persistWalletState()
        }
        currentUser = user
        recordAuditEvent(
            userId: user.id,
            actorUserId: user.id,
            type: .auth,
            title: "Social registration",
            message: "Реєстрація через \(provider)",
            relatedId: user.id
        )
        shouldRequestLocationPermission = false
        authErrorMessage = nil
        resetPhoneVerificationSession()
        persistAuthState()
        persistAuditState()
        return true
    }

    private func generateUniqueDemoPhone() -> String {
        var phone: String
        repeat {
            let suffix = String(format: "%09d", Int.random(in: 0...999_999_999))
            phone = "380\(suffix)"
        } while users.contains(where: { $0.phone == phone })
        return phone
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
        emailVerificationStep = .enterChangeEmails
        emailVerificationDemoCode = ""
        pendingNewEmailForChange = ""
        authErrorMessage = nil
    }

    func startEmailChange(oldEmail: String, newEmail: String) -> Bool {
        guard emailVerificationStep == .enterChangeEmails else { return false }
        guard let currentUser else { return false }

        let normalizedOld = oldEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedNew = newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard normalizedOld == currentUser.email.lowercased() else {
            authErrorMessage = "Стара пошта не збігається з поточною"
            return false
        }

        guard isValidEmail(normalizedNew) else {
            authErrorMessage = "Введіть коректний email"
            return false
        }

        guard normalizedNew != normalizedOld else {
            authErrorMessage = "Нова пошта має відрізнятися від старої"
            return false
        }

        pendingNewEmailForChange = normalizedNew
        emailVerificationStep = .verifyOldEmail
        emailVerificationDemoCode = generate4DigitCode()
        authErrorMessage = nil
        return true
    }

    func confirmOldEmailForChange(code: String) -> Bool {
        guard emailVerificationStep == .verifyOldEmail else { return false }
        guard code.trimmingCharacters(in: .whitespacesAndNewlines) == emailVerificationDemoCode else {
            authErrorMessage = "Невірний код зі старої пошти"
            return false
        }

        emailVerificationStep = .verifyNewEmail
        emailVerificationDemoCode = generate4DigitCode()
        authErrorMessage = nil
        return true
    }

    func confirmNewEmailForChange(code: String) -> Bool {
        guard emailVerificationStep == .verifyNewEmail else { return false }
        guard code.trimmingCharacters(in: .whitespacesAndNewlines) == emailVerificationDemoCode else {
            authErrorMessage = "Невірний код з нової пошти"
            return false
        }
        guard let currentUser, let index = users.firstIndex(where: { $0.id == currentUser.id }) else { return false }
        guard !pendingNewEmailForChange.isEmpty else {
            authErrorMessage = "Помилка зміни пошти. Спробуйте ще раз"
            emailVerificationStep = .none
            emailVerificationDemoCode = ""
            return false
        }
        users[index].email = pendingNewEmailForChange
        users[index].isEmailVerified = true
        self.currentUser = users[index]
        emailVerificationStep = .none
        emailVerificationDemoCode = ""
        pendingNewEmailForChange = ""
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
        if let currentUser {
            recordAuditEvent(
                userId: currentUser.id,
                actorUserId: currentUser.id,
                type: .auth,
                title: "Logout",
                message: "Користувач вийшов з акаунту",
                relatedId: currentUser.id
            )
        }
        currentUser = nil
        shouldRequestLocationPermission = false
        resetPhoneVerificationSession()
        persistAuthState()
        persistAuditState()
    }

    func addShift(title: String, details: String, address: String, pay: Int, startDate: Date, endDate: Date, coordinate: CLLocationCoordinate2D, workFormat: WorkFormat, requiredWorkers: Int) {
        guard let currentUser, currentUser.role == .employer else { return }
        let finalCoordinate = UkraineRegion.contains(coordinate) ? coordinate : UkraineRegion.center
        let cityName = cityNameForCoordinate(finalCoordinate)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAddress = trimmedAddress.isEmpty ? "м. \(cityName), локація на мапі" : trimmedAddress

        shifts.append(
            JobShift(
                id: UUID(),
                title: title,
                details: details,
                address: finalAddress,
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
        let cooldownSeconds = noShowCooldownRemaining(for: currentUser.id)
        if cooldownSeconds > 0 {
            let hours = max(1, cooldownSeconds / 3600)
            authErrorMessage = "Тимчасове обмеження через пропущені зміни. Спробуйте через \(hours) год."
            return
        }
        if riskLevel(for: currentUser.id) == .high {
            authErrorMessage = "Заявку тимчасово обмежено: високий ризик профілю. Подайте апеляцію в профілі."
            return
        }
        guard let shift = shift(by: shiftId), shift.status == .open, !isShiftFull(shift) else { return }
        guard !applications.contains(where: { $0.shiftId == shiftId && $0.workerId == currentUser.id }) else { return }

        let convo = ensureConversation(shiftId: shiftId, workerId: currentUser.id)

        let createdAt = Date()
        applications.append(
            ShiftApplication(
                id: UUID(),
                shiftId: shiftId,
                workerId: currentUser.id,
                status: .pending,
                progressStatus: .scheduled,
                createdAt: createdAt,
                respondBy: Calendar.current.date(byAdding: .hour, value: employerResponseSLAHours, to: createdAt) ?? createdAt
            )
        )
        if let convo {
            chatMessages.append(
                ChatMessage(
                    id: UUID(),
                    conversationId: convo.id,
                    shiftId: shiftId,
                    senderId: nil,
                    senderRole: .system,
                    text: "Працівник відгукнувся на зміну. Можна обговорити умови в чаті.",
                    createdAt: createdAt,
                    isEdited: false,
                    offerId: nil
                )
            )
            if let index = conversations.firstIndex(where: { $0.id == convo.id }) {
                conversations[index].lastMessageAt = createdAt
                conversations[index].workerLastReadAt = createdAt
            }
        }

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
        authErrorMessage = nil
    }

    func updateApplicationStatus(applicationId: UUID, status: ApplicationStatus) {
        guard let index = applications.firstIndex(where: { $0.id == applicationId }) else { return }
        let oldStatus = applications[index].status
        let workerId = applications[index].workerId

        let shiftId = applications[index].shiftId
        if status == .accepted,
           let shift = shift(by: shiftId),
           acceptedApplicationsCount(for: shift.id) >= shift.requiredWorkers,
           applications[index].status != .accepted {
            return
        }

        if status == .accepted,
           oldStatus != .accepted,
           let shift = shift(by: shiftId) {
            let needed = paymentBreakdown(for: shift, workersCount: 1).employerTotalAmount
            let available = employerEscrowAvailableAmount(for: shift.employerId)
            if available < needed {
                authErrorMessage = "Недостатньо коштів в ескроу. Потрібно \(needed) грн, доступно \(available) грн."
                return
            }
        }

        applications[index].status = status
        if status == .accepted {
            ensurePayoutRecord(for: applications[index])
            updatePayoutRecordStatus(
                applicationId: applications[index].id,
                status: .reserved,
                note: "Кошти зарезервовано під зміну"
            )
        } else {
            updatePayoutRecordStatus(
                applicationId: applications[index].id,
                status: .canceled,
                note: status == .rejected ? "Заявку відхилено" : "Заявку скасовано"
            )
        }
        if status != .accepted {
            applications[index].progressStatus = .scheduled
        }
        if status != .pending {
            reminderTimestamps[applications[index].id] = nil
        }
        if oldStatus != status {
            notifyStatusChangeIfNeeded(for: applications[index])
            if let convo = ensureConversation(shiftId: shiftId, workerId: workerId) {
                let statusText = "Статус заявки: \(status.title)."
                let stamp = Date()
                chatMessages.append(
                    ChatMessage(
                        id: UUID(),
                        conversationId: convo.id,
                        shiftId: shiftId,
                        senderId: nil,
                        senderRole: .system,
                        text: statusText,
                        createdAt: stamp,
                        isEdited: false,
                        offerId: nil
                    )
                )
                if let convoIndex = conversations.firstIndex(where: { $0.id == convo.id }) {
                    conversations[convoIndex].lastMessageAt = stamp
                }
            }
        }
        syncShiftCapacity(for: shiftId)
        refreshReliability(for: applications[index])
        persistWalletState()
    }

    func updateWorkProgressStatus(applicationId: UUID, to newStatus: WorkProgressStatus) -> Bool {
        guard let index = applications.firstIndex(where: { $0.id == applicationId }) else { return false }
        guard applications[index].status == .accepted else { return false }
        guard let shift = shift(by: applications[index].shiftId) else { return false }
        guard let employer = currentUser, employer.id == shift.employerId, employer.role == .employer else { return false }

        let currentStatus = applications[index].progressStatus
        guard canMoveProgress(from: currentStatus, to: newStatus) else { return false }
        if newStatus == .paid, activeDispute(for: applicationId) != nil {
            authErrorMessage = "Неможливо провести оплату, поки спір активний"
            return false
        }

        applications[index].progressStatus = newStatus
        ensurePayoutRecord(for: applications[index])
        switch newStatus {
        case .scheduled:
            updatePayoutRecordStatus(applicationId: applicationId, status: .reserved, note: "Зміна запланована")
        case .inProgress:
            updatePayoutRecordStatus(applicationId: applicationId, status: .reserved, note: "Зміна в роботі")
        case .completed:
            let status: PayoutStatus = activeDispute(for: applicationId) == nil ? .pendingRelease : .onHold
            updatePayoutRecordStatus(applicationId: applicationId, status: status, note: status == .pendingRelease ? "Очікує виплату" : "Виплату поставлено на холд")
        case .paid:
            updatePayoutRecordStatus(applicationId: applicationId, status: .paid, note: "Виплату підтверджено")
        }
        notifyWorkProgressChanged(application: applications[index], shift: shift, old: currentStatus, new: newStatus)
        refreshReliability(for: applications[index])
        return true
    }

    func advanceWorkProgressStatus(applicationId: UUID) -> Bool {
        guard let application = applications.first(where: { $0.id == applicationId }) else { return false }
        let nextStatus: WorkProgressStatus
        switch application.progressStatus {
        case .scheduled:
            nextStatus = .inProgress
        case .inProgress:
            nextStatus = .completed
        case .completed:
            nextStatus = .paid
        case .paid:
            return false
        }
        return updateWorkProgressStatus(applicationId: applicationId, to: nextStatus)
    }

    func guaranteeStateText(for application: ShiftApplication) -> String {
        if activeDispute(for: application.id) != nil {
            return "По зміні активний спір. Виплату тимчасово призупинено до рішення."
        }
        switch application.progressStatus {
        case .scheduled:
            return "Зміна запланована. Оплата буде зафіксована після завершення роботи."
        case .inProgress:
            return "Зміна в роботі. Оплата зарезервована до завершення."
        case .completed:
            return "Роботу завершено. Планова виплата: протягом 24 годин."
        case .paid:
            return "Оплату підтверджено."
        }
    }

    private func canMoveProgress(from oldStatus: WorkProgressStatus, to newStatus: WorkProgressStatus) -> Bool {
        switch (oldStatus, newStatus) {
        case (.scheduled, .inProgress), (.inProgress, .completed), (.completed, .paid):
            return true
        default:
            return false
        }
    }

    private func notifyWorkProgressChanged(application: ShiftApplication, shift: JobShift, old: WorkProgressStatus, new: WorkProgressStatus) {
        guard old != new else { return }
        let workerName = user(by: application.workerId)?.name ?? "Працівник"

        addInAppNotification(
            for: application.workerId,
            title: "Оновлено статус оплати",
            message: "Зміна «\(shift.title)»: \(new.title).",
            kind: new == .paid ? .success : .info
        )

        addInAppNotification(
            for: shift.employerId,
            title: "Статус співпраці оновлено",
            message: "\(workerName): \(new.title.lowercased()) по зміні «\(shift.title)».",
            kind: .info
        )

        if let convo = ensureConversation(shiftId: application.shiftId, workerId: application.workerId),
           let convoIndex = conversations.firstIndex(where: { $0.id == convo.id }) {
            let stamp = Date()
            chatMessages.append(
                ChatMessage(
                    id: UUID(),
                    conversationId: convo.id,
                    shiftId: application.shiftId,
                    senderId: nil,
                    senderRole: .system,
                    text: "Етап виконання змінено: \(new.title).",
                    createdAt: stamp,
                    isEdited: false,
                    offerId: nil
                )
            )
            conversations[convoIndex].lastMessageAt = stamp
        }
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

    func executionEvents(for applicationId: UUID) -> [ShiftExecutionEvent] {
        shiftExecutionEvents
            .filter { $0.applicationId == applicationId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func activeDispute(for applicationId: UUID) -> ShiftDispute? {
        shiftDisputes
            .first(where: { $0.applicationId == applicationId && ($0.status == .open || $0.status == .inReview) })
    }

    func disputesForCurrentUser() -> [ShiftDispute] {
        guard let currentUser else { return [] }
        return shiftDisputes
            .filter { dispute in
                guard let shift = shift(by: dispute.shiftId),
                      let application = applications.first(where: { $0.id == dispute.applicationId }) else { return false }
                return shift.employerId == currentUser.id || application.workerId == currentUser.id
            }
            .sorted { lhs, rhs in
                let lhsResolved = lhs.status == .resolvedForWorker || lhs.status == .resolvedForEmployer
                let rhsResolved = rhs.status == .resolvedForWorker || rhs.status == .resolvedForEmployer
                if lhsResolved != rhsResolved {
                    return rhsResolved
                }
                return lhs.openedAt > rhs.openedAt
            }
    }

    func disputeUpdates(for disputeId: UUID) -> [DisputeUpdate] {
        disputeUpdates
            .filter { $0.disputeId == disputeId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func disputeSecondsRemaining(_ dispute: ShiftDispute, now: Date = Date()) -> Int? {
        guard dispute.status == .open else { return nil }
        return max(0, Int(dispute.slaDueAt.timeIntervalSince(now)))
    }

    func payoutRecord(for applicationId: UUID) -> PayoutRecord? {
        payoutRecords.first(where: { $0.applicationId == applicationId })
    }

    func employerWalletBalance(for employerId: UUID) -> Int {
        walletBalances[employerId] ?? 0
    }

    func employerEscrowReservedAmount(for employerId: UUID) -> Int {
        payoutRecords
            .filter { $0.employerId == employerId && isEscrowReserved($0.status) }
            .reduce(0) { $0 + $1.employerTotalAmount }
    }

    func employerEscrowAvailableAmount(for employerId: UUID) -> Int {
        max(0, employerWalletBalance(for: employerId) - employerEscrowReservedAmount(for: employerId))
    }

    func currentEmployerEscrowSnapshot() -> (balance: Int, reserved: Int, available: Int)? {
        guard let currentUser, currentUser.role == .employer else { return nil }
        let balance = employerWalletBalance(for: currentUser.id)
        let reserved = employerEscrowReservedAmount(for: currentUser.id)
        let available = max(0, balance - reserved)
        return (balance, reserved, available)
    }

    func escrowReconciliationReport(for employerId: UUID, now: Date = Date()) -> EscrowReconciliationReport {
        let walletBalance = employerWalletBalance(for: employerId)
        let ledgerBalance = walletTransactions
            .filter { $0.employerId == employerId }
            .reduce(0) { partial, tx in
                let magnitude = abs(tx.amount)
                switch tx.type {
                case .topUp, .refund, .release:
                    return partial + magnitude
                case .reserve, .payout:
                    return partial - magnitude
                }
            }
        let reservedAmount = employerEscrowReservedAmount(for: employerId)
        let pendingPayoutAmount = payoutRecords
            .filter { $0.employerId == employerId && $0.status == .pendingRelease }
            .reduce(0) { $0 + $1.employerTotalAmount }
        let paidAmount = payoutRecords
            .filter { $0.employerId == employerId && $0.status == .paid }
            .reduce(0) { $0 + $1.employerTotalAmount }

        let expectedAvailable = ledgerBalance - reservedAmount
        let actualAvailable = employerEscrowAvailableAmount(for: employerId)
        let mismatchAmount = walletBalance - ledgerBalance

        return EscrowReconciliationReport(
            employerId: employerId,
            walletBalance: walletBalance,
            reservedAmount: reservedAmount,
            pendingPayoutAmount: pendingPayoutAmount,
            paidAmount: paidAmount,
            expectedAvailable: max(0, expectedAvailable),
            actualAvailable: actualAvailable,
            mismatchAmount: mismatchAmount,
            generatedAt: now
        )
    }

    func currentEmployerEscrowReconciliationReport() -> EscrowReconciliationReport? {
        guard let currentUser, currentUser.role == .employer else { return nil }
        return escrowReconciliationReport(for: currentUser.id)
    }

    @discardableResult
    func runCurrentEmployerReconciliationAudit() -> Bool {
        guard let currentUser, currentUser.role == .employer else { return false }
        let report = escrowReconciliationReport(for: currentUser.id)
        let message = "Баланс: \(report.walletBalance), резерв: \(report.reservedAmount), mismatch: \(report.mismatchAmount)"
        recordAuditEvent(
            userId: currentUser.id,
            actorUserId: currentUser.id,
            type: .escrow,
            title: report.isHealthy ? "Reconciliation OK" : "Reconciliation mismatch",
            message: message,
            relatedId: currentUser.id
        )
        return report.isHealthy
    }

    @discardableResult
    func topUpCurrentEmployerWallet(by amount: Int) -> Bool {
        guard let currentUser, currentUser.role == .employer else { return false }
        let normalized = max(0, amount)
        guard normalized > 0 else { return false }
        walletBalances[currentUser.id, default: employerInitialDemoBalance] += normalized
        recordWalletTransaction(
            employerId: currentUser.id,
            payoutRecordId: nil,
            applicationId: nil,
            type: .topUp,
            amount: normalized,
            note: "Поповнення балансу роботодавця"
        )
        persistWalletState()
        return true
    }

    func recentWalletTransactions(for employerId: UUID, limit: Int = 8) -> [WalletTransaction] {
        walletTransactions
            .filter { $0.employerId == employerId }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func auditEventsForCurrentUser(
        type: AuditEventType? = nil,
        since: Date? = nil,
        limit: Int = 40
    ) -> [AuditEvent] {
        guard let currentUser else { return [] }
        return auditEvents
            .filter { event in
                let visible = event.userId == nil || event.userId == currentUser.id || event.actorUserId == currentUser.id
                let typeMatch = type == nil || event.type == type
                let dateMatch = since == nil || event.createdAt >= since!
                return visible && typeMatch && dateMatch
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func moderationCasesForCurrentUser() -> [ModerationCase] {
        guard let currentUser else { return [] }
        return moderationCases
            .filter { $0.userId == currentUser.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func moderationAgents() -> [AppUser] {
        users
            .filter { $0.role == .employer && $0.moderationRole.canReviewCases }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func currentUserCanAccessModeration() -> Bool {
        guard let currentUser else { return false }
        return currentUser.role == .employer && currentUser.moderationRole.canReviewCases
    }

    func currentUserCanAssignModeration() -> Bool {
        guard let currentUser else { return false }
        return currentUser.role == .employer && currentUser.moderationRole.canAssignCases
    }

    func currentUserCanManageModerators() -> Bool {
        guard let currentUser else { return false }
        return currentUser.role == .employer && currentUser.moderationRole == .lead
    }

    func moderationCaseAssigneeName(_ item: ModerationCase) -> String {
        guard let assignedId = item.assignedModeratorId else { return "Не призначено" }
        return users.first(where: { $0.id == assignedId })?.name ?? "Невідомий агент"
    }

    func moderationActions(for caseId: UUID, limit: Int = 10) -> [ModerationCaseAction] {
        moderationActions
            .filter { $0.caseId == caseId }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    @discardableResult
    func assignModerationRole(userId: UUID, role: ModerationRole) -> Bool {
        guard currentUserCanManageModerators(),
              let targetIndex = users.firstIndex(where: { $0.id == userId && $0.role == .employer }) else { return false }

        let previousRole = users[targetIndex].moderationRole
        guard previousRole != role else { return true }

        // Keep at least one lead in the system.
        if previousRole == .lead && role != .lead {
            let otherLeadExists = users.contains(where: {
                $0.id != userId && $0.role == .employer && $0.moderationRole == .lead
            })
            if !otherLeadExists {
                return false
            }
        }

        users[targetIndex].moderationRole = role
        if let currentUser, currentUser.id == users[targetIndex].id {
            self.currentUser = users[targetIndex]
        }

        // Unassign open cases from users who lost moderation privileges.
        if !role.canReviewCases {
            for caseIndex in moderationCases.indices where moderationCases[caseIndex].assignedModeratorId == userId {
                moderationCases[caseIndex].assignedModeratorId = nil
                moderationCases[caseIndex].status = .open
                moderationCases[caseIndex].updatedAt = Date()
                recordModerationAction(
                    caseId: moderationCases[caseIndex].id,
                    actorUserId: currentUser?.id,
                    assignedModeratorId: nil,
                    type: .assigned,
                    note: "Призначення знято: роль модератора змінена"
                )
            }
        }

        recordAuditEvent(
            userId: userId,
            actorUserId: currentUser?.id,
            type: .moderation,
            title: "Оновлено роль модератора",
            message: "\(previousRole.title) → \(role.title)",
            relatedId: userId
        )
        persistAuthState()
        persistModerationState()
        return true
    }

    func moderationQueueOpenCases() -> [ModerationCase] {
        moderationCases
            .filter { $0.status == .open || $0.status == .inReview }
            .sorted { lhs, rhs in
                let lhsOverdue = moderationIsOverdue(lhs)
                let rhsOverdue = moderationIsOverdue(rhs)
                if lhsOverdue != rhsOverdue {
                    return lhsOverdue && !rhsOverdue
                }
                let lhsPriority = moderationPriorityValue(lhs)
                let rhsPriority = moderationPriorityValue(rhs)
                if lhsPriority != rhsPriority {
                    return lhsPriority > rhsPriority
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func moderationSLAHours(for type: ModerationCaseType) -> Int {
        switch type {
        case .riskAppeal:
            return 2
        case .kyc:
            return 6
        }
    }

    func moderationAgeHours(_ item: ModerationCase, now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(item.createdAt) / 3600))
    }

    func moderationIsOverdue(_ item: ModerationCase, now: Date = Date()) -> Bool {
        moderationAgeHours(item, now: now) >= moderationSLAHours(for: item.type)
    }

    private func moderationPriorityValue(_ item: ModerationCase, now: Date = Date()) -> Int {
        var score = 0
        if moderationIsOverdue(item, now: now) { score += 100 }
        if item.type == .riskAppeal { score += 30 }
        if item.status == .open { score += 10 }
        if item.assignedModeratorId == nil { score += 5 }
        return score
    }

    private func canCurrentUserResolveModerationCase(_ item: ModerationCase) -> Bool {
        guard let currentUser,
              currentUser.role == .employer,
              currentUser.moderationRole.canReviewCases else { return false }
        if currentUser.moderationRole.canResolveAnyCase { return true }
        return item.assignedModeratorId == currentUser.id
    }

    @discardableResult
    func submitEmployerKYC(companyName: String, taxId: String) -> Bool {
        guard let currentUser, currentUser.role == .employer else { return false }
        let normalizedCompany = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTaxId = taxId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCompany.count >= 2 else {
            authErrorMessage = "Вкажіть назву компанії"
            return false
        }
        guard normalizedTaxId.count >= 6 else {
            authErrorMessage = "Вкажіть коректний Tax ID"
            return false
        }
        guard let userIndex = users.firstIndex(where: { $0.id == currentUser.id }) else { return false }
        users[userIndex].employerCompanyName = normalizedCompany
        users[userIndex].employerTaxId = normalizedTaxId
        users[userIndex].employerKYCStatus = .pending
        users[userIndex].isVerifiedEmployer = false
        users[userIndex].kycReviewNote = "Заявку передано на перевірку"
        self.currentUser = users[userIndex]

        createOrRefreshModerationCase(
            userId: currentUser.id,
            type: .kyc,
            subject: "KYC: \(normalizedCompany)",
            details: "Tax ID: \(normalizedTaxId)",
            status: .open
        )
        addInAppNotification(
            for: currentUser.id,
            title: "KYC надіслано",
            message: "Верифікацію роботодавця передано на модерацію.",
            kind: .info
        )
        authErrorMessage = nil
        persistAuthState()
        persistModerationState()
        persistAuditState()
        return true
    }

    @discardableResult
    func submitRiskAppeal(reason: String) -> Bool {
        guard let currentUser else { return false }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedReason.count >= 8 else {
            authErrorMessage = "Опишіть причину апеляції детальніше"
            return false
        }
        createOrRefreshModerationCase(
            userId: currentUser.id,
            type: .riskAppeal,
            subject: "Risk appeal",
            details: normalizedReason,
            status: .open
        )
        addInAppNotification(
            for: currentUser.id,
            title: "Апеляцію прийнято",
            message: "Кейс передано на перевірку підтримки.",
            kind: .info
        )
        authErrorMessage = nil
        persistModerationState()
        persistAuditState()
        return true
    }

    @discardableResult
    func demoResolveMyModerationCase(type: ModerationCaseType, approve: Bool, note: String) -> Bool {
        guard let currentUser else { return false }
        guard let caseIndex = moderationCases.firstIndex(where: {
            $0.userId == currentUser.id && $0.type == type && ($0.status == .open || $0.status == .inReview)
        }) else { return false }

        moderationCases[caseIndex].status = approve ? .resolvedApproved : .resolvedRejected
        moderationCases[caseIndex].updatedAt = Date()
        moderationCases[caseIndex].resolutionNote = note

        if let userIndex = users.firstIndex(where: { $0.id == currentUser.id }) {
            switch type {
            case .kyc:
                users[userIndex].employerKYCStatus = approve ? .verified : .rejected
                users[userIndex].isVerifiedEmployer = approve
                users[userIndex].kycReviewNote = note
            case .riskAppeal:
                if approve {
                    reduceRiskSignals(for: currentUser.id, note: note)
                }
            }
            self.currentUser = users[userIndex]
        }

        addInAppNotification(
            for: currentUser.id,
            title: type == .kyc ? "KYC оновлено" : "Апеляцію розглянуто",
            message: approve ? "Рішення позитивне." : "Рішення негативне.",
            kind: approve ? .success : .warning
        )
        recordAuditEvent(
            userId: currentUser.id,
            actorUserId: currentUser.id,
            type: .moderation,
            title: type == .kyc ? "KYC рішення (demo)" : "Risk appeal рішення (demo)",
            message: note,
            relatedId: moderationCases[caseIndex].id
        )
        recordModerationAction(
            caseId: moderationCases[caseIndex].id,
            actorUserId: currentUser.id,
            assignedModeratorId: currentUser.id,
            type: approve ? .resolvedApproved : .resolvedRejected,
            note: note
        )
        persistAuthState()
        persistModerationState()
        return true
    }

    @discardableResult
    func processModerationCase(caseId: UUID, approve: Bool, note: String) -> Bool {
        guard let currentUser,
              currentUser.role == .employer,
              currentUser.moderationRole.canReviewCases,
              let caseIndex = moderationCases.firstIndex(where: { $0.id == caseId }) else { return false }
        let targetCase = moderationCases[caseIndex]
        guard targetCase.status == .open || targetCase.status == .inReview else { return false }
        guard canCurrentUserResolveModerationCase(targetCase) else { return false }

        moderationCases[caseIndex].status = approve ? .resolvedApproved : .resolvedRejected
        moderationCases[caseIndex].updatedAt = Date()
        moderationCases[caseIndex].resolutionNote = note

        if let userIndex = users.firstIndex(where: { $0.id == targetCase.userId }) {
            switch targetCase.type {
            case .kyc:
                users[userIndex].employerKYCStatus = approve ? .verified : .rejected
                users[userIndex].isVerifiedEmployer = approve
                users[userIndex].kycReviewNote = note
            case .riskAppeal:
                if approve {
                    reduceRiskSignals(for: targetCase.userId, note: note)
                }
            }
            if currentUser.id == users[userIndex].id {
                self.currentUser = users[userIndex]
            }
        }

        addInAppNotification(
            for: targetCase.userId,
            title: targetCase.type == .kyc ? "KYC оновлено" : "Апеляцію розглянуто",
            message: approve ? "Кейс схвалено модератором." : "Кейс відхилено модератором.",
            kind: approve ? .success : .warning
        )
        recordAuditEvent(
            userId: targetCase.userId,
            actorUserId: currentUser.id,
            type: .moderation,
            title: approve ? "Кейс схвалено" : "Кейс відхилено",
            message: note,
            relatedId: targetCase.id
        )
        recordModerationAction(
            caseId: targetCase.id,
            actorUserId: currentUser.id,
            assignedModeratorId: moderationCases[caseIndex].assignedModeratorId,
            type: approve ? .resolvedApproved : .resolvedRejected,
            note: note
        )
        persistAuthState()
        persistModerationState()
        return true
    }

    @discardableResult
    func startModerationReview(caseId: UUID) -> Bool {
        guard let currentUser,
              currentUser.role == .employer,
              currentUser.moderationRole.canReviewCases,
              let caseIndex = moderationCases.firstIndex(where: { $0.id == caseId }) else { return false }
        guard moderationCases[caseIndex].status == .open else { return false }
        if currentUser.moderationRole == .agent,
           let assignedModeratorId = moderationCases[caseIndex].assignedModeratorId,
           assignedModeratorId != currentUser.id {
            return false
        }
        moderationCases[caseIndex].assignedModeratorId = currentUser.id
        moderationCases[caseIndex].status = .inReview
        moderationCases[caseIndex].updatedAt = Date()
        recordAuditEvent(
            userId: moderationCases[caseIndex].userId,
            actorUserId: currentUser.id,
            type: .moderation,
            title: "Кейс взято в роботу",
            message: moderationCases[caseIndex].subject,
            relatedId: caseId
        )
        recordModerationAction(
            caseId: caseId,
            actorUserId: currentUser.id,
            assignedModeratorId: currentUser.id,
            type: .startedReview,
            note: moderationCases[caseIndex].subject
        )
        persistModerationState()
        return true
    }

    @discardableResult
    func assignModerationCase(caseId: UUID, to assigneeId: UUID?) -> Bool {
        guard let currentUser,
              currentUser.role == .employer,
              currentUser.moderationRole.canReviewCases,
              let caseIndex = moderationCases.firstIndex(where: { $0.id == caseId }) else { return false }
        guard moderationCases[caseIndex].status == .open || moderationCases[caseIndex].status == .inReview else { return false }

        if let assigneeId {
            guard let assignee = users.first(where: { $0.id == assigneeId }),
                  assignee.role == .employer,
                  assignee.moderationRole.canReviewCases else { return false }
            if currentUser.moderationRole == .agent && assigneeId != currentUser.id {
                return false
            }
        } else if !currentUser.moderationRole.canAssignCases {
            return false
        }

        moderationCases[caseIndex].assignedModeratorId = assigneeId
        moderationCases[caseIndex].updatedAt = Date()

        let note = assigneeId.flatMap { id in
            users.first(where: { $0.id == id })?.name
        } ?? "Призначення знято"
        recordModerationAction(
            caseId: caseId,
            actorUserId: currentUser.id,
            assignedModeratorId: assigneeId,
            type: .assigned,
            note: note
        )
        recordAuditEvent(
            userId: moderationCases[caseIndex].userId,
            actorUserId: currentUser.id,
            type: .moderation,
            title: "Кейс перепризначено",
            message: note,
            relatedId: caseId
        )
        persistModerationState()
        return true
    }

    func riskSignalsForUser(_ userId: UUID) -> [RiskSignal] {
        riskSignals
            .filter { $0.userId == userId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func riskScore(for userId: UUID, now: Date = Date()) -> Double {
        let signals = riskSignalsForUser(userId)
        guard !signals.isEmpty else { return 0 }
        let window = now.addingTimeInterval(-14 * 24 * 3600)
        let recent = signals.filter { $0.createdAt >= window }
        let target: [RiskSignal] = recent.isEmpty ? Array(signals.prefix(5)) : recent
        let weighted = target.reduce(0.0) { partial, signal in
            let value: Double
            switch signal.level {
            case .low:
                value = 10
            case .medium:
                value = 25
            case .high:
                value = 45
            }
            return partial + value
        }
        return min(100, weighted)
    }

    func riskLevel(for userId: UUID, now: Date = Date()) -> RiskLevel {
        let score = riskScore(for: userId, now: now)
        if score >= 60 { return .high }
        if score >= 25 { return .medium }
        return .low
    }

    func noShowCooldownRemaining(for workerId: UUID, now: Date = Date()) -> Int {
        guard let date = latestNoShowDate(for: workerId, now: now) else { return 0 }
        let cooldownEnd = date.addingTimeInterval(TimeInterval(noShowCooldownHours * 3600))
        return max(0, Int(cooldownEnd.timeIntervalSince(now)))
    }

    func disputeSLAStatusText(_ dispute: ShiftDispute, now: Date = Date()) -> String {
        switch dispute.status {
        case .open:
            let seconds = Int(dispute.slaDueAt.timeIntervalSince(now))
            if seconds <= 0 {
                return "SLA прострочено, кейс ескалюється"
            }
            let mins = max(1, seconds / 60)
            return "SLA до ескалації: \(mins) хв"
        case .inReview:
            return "Підтримка розглядає кейс"
        case .resolvedForWorker, .resolvedForEmployer:
            return "Кейс закрито"
        }
    }

    @discardableResult
    func startDisputeReview(disputeId: UUID) -> Bool {
        guard let currentUser,
              let disputeIndex = shiftDisputes.firstIndex(where: { $0.id == disputeId }),
              let shift = shift(by: shiftDisputes[disputeIndex].shiftId),
              shiftDisputes[disputeIndex].status == .open else { return false }

        guard currentUser.id == shift.employerId else { return false }
        shiftDisputes[disputeIndex].status = .inReview
        shiftDisputes[disputeIndex].escalatedAt = Date()
        appendDisputeUpdate(
            disputeId: shiftDisputes[disputeIndex].id,
            actorUserId: currentUser.id,
            actorTitle: "Роботодавець",
            message: "Кейс взято в розгляд"
        )
        addInAppNotification(
            for: currentUser.id,
            title: "Спір взято в роботу",
            message: "Ви перевели спір у розгляд.",
            kind: .info
        )
        if let application = applications.first(where: { $0.id == shiftDisputes[disputeIndex].applicationId }) {
            addInAppNotification(
                for: application.workerId,
                title: "Спір у розгляді",
                message: "Роботодавець взяв спір по зміні «\(shift.title)» в роботу.",
                kind: .info
            )
        }
        return true
    }

    func checkIn(applicationId: UUID, coordinate: CLLocationCoordinate2D? = nil) -> Bool {
        guard let currentUser,
              let appIndex = applications.firstIndex(where: { $0.id == applicationId }) else { return false }

        let application = applications[appIndex]
        guard application.workerId == currentUser.id,
              application.status == .accepted,
              application.progressStatus == .scheduled else { return false }

        applications[appIndex].progressStatus = .inProgress
        ensurePayoutRecord(for: applications[appIndex])
        updatePayoutRecordStatus(
            applicationId: applications[appIndex].id,
            status: .reserved,
            note: "Працівник зачекинився"
        )
        appendExecutionEvent(
            shiftId: application.shiftId,
            applicationId: application.id,
            actorUserId: currentUser.id,
            type: .checkIn,
            note: "Працівник відмітив початок зміни",
            coordinate: coordinate
        )

        if let shift = shift(by: application.shiftId) {
            addInAppNotification(
                for: shift.employerId,
                title: "Працівник на зміні",
                message: "\(currentUser.name) розпочав(ла) зміну «\(shift.title)».",
                kind: .info
            )
        }
        refreshReliability(for: applications[appIndex])
        return true
    }

    func checkOut(applicationId: UUID, coordinate: CLLocationCoordinate2D? = nil) -> Bool {
        guard let currentUser,
              let appIndex = applications.firstIndex(where: { $0.id == applicationId }) else { return false }

        let application = applications[appIndex]
        guard application.workerId == currentUser.id,
              application.status == .accepted,
              application.progressStatus == .inProgress else { return false }

        applications[appIndex].progressStatus = .completed
        ensurePayoutRecord(for: applications[appIndex])
        let payoutStatus: PayoutStatus = activeDispute(for: applications[appIndex].id) == nil ? .pendingRelease : .onHold
        updatePayoutRecordStatus(
            applicationId: applications[appIndex].id,
            status: payoutStatus,
            note: payoutStatus == .pendingRelease ? "Зміну завершено, готуємо виплату" : "Зміну завершено, виплату поставлено на холд"
        )
        appendExecutionEvent(
            shiftId: application.shiftId,
            applicationId: application.id,
            actorUserId: currentUser.id,
            type: .checkOut,
            note: "Працівник завершив зміну",
            coordinate: coordinate
        )

        if let shift = shift(by: application.shiftId) {
            addInAppNotification(
                for: shift.employerId,
                title: "Зміну завершено",
                message: "\(currentUser.name) завершив(ла) зміну «\(shift.title)». Підтвердіть оплату.",
                kind: .warning
            )
        }
        refreshReliability(for: applications[appIndex])
        return true
    }

    @discardableResult
    func openDispute(applicationId: UUID, category: DisputeCategory = .other, reason: String) -> Bool {
        guard let currentUser,
              let application = applications.first(where: { $0.id == applicationId }),
              let shift = shift(by: application.shiftId),
              reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return false }

        guard application.status == .accepted else { return false }
        guard activeDispute(for: applicationId) == nil else {
            authErrorMessage = "Спір по цій зміні вже відкрито"
            return false
        }

        let isAllowedActor = currentUser.id == shift.employerId || currentUser.id == application.workerId
        guard isAllowedActor else { return false }

        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let dispute = ShiftDispute(
            id: UUID(),
            shiftId: shift.id,
            applicationId: application.id,
            openedByUserId: currentUser.id,
            openedAt: now,
            slaDueAt: now.addingTimeInterval(TimeInterval(disputeSLAOpenMinutes * 60)),
            category: category,
            reason: normalizedReason,
            status: .open,
            escalatedAt: nil,
            resolvedAt: nil,
            resolutionNote: nil
        )
        shiftDisputes.append(dispute)
        detectExcessiveDisputesRisk(for: currentUser.id, now: now)
        appendDisputeUpdate(
            disputeId: dispute.id,
            actorUserId: currentUser.id,
            actorTitle: currentUser.role == .worker ? "Працівник" : "Роботодавець",
            message: "Створено спір [\(category.title)]: \(normalizedReason)"
        )
        appendExecutionEvent(
            shiftId: shift.id,
            applicationId: application.id,
            actorUserId: currentUser.id,
            type: .disputeOpened,
            note: normalizedReason,
            coordinate: nil
        )
        updatePayoutRecordStatus(
            applicationId: application.id,
            status: .onHold,
            note: "Спір відкрито: \(category.title)"
        )

        let counterpartyId = currentUser.id == shift.employerId ? application.workerId : shift.employerId
        addInAppNotification(
            for: counterpartyId,
            title: "Відкрито спір",
            message: "По зміні «\(shift.title)» відкрито спір. Підтримка підключиться автоматично.",
            kind: .warning
        )
        authErrorMessage = nil
        return true
    }

    @discardableResult
    func resolveDispute(disputeId: UUID, inFavorOfWorker: Bool, note: String) -> Bool {
        guard let currentUser,
              let disputeIndex = shiftDisputes.firstIndex(where: { $0.id == disputeId }),
              let shift = shift(by: shiftDisputes[disputeIndex].shiftId),
              let applicationIndex = applications.firstIndex(where: { $0.id == shiftDisputes[disputeIndex].applicationId }) else { return false }

        guard currentUser.id == shift.employerId else { return false }
        guard shiftDisputes[disputeIndex].status == .open || shiftDisputes[disputeIndex].status == .inReview else { return false }

        shiftDisputes[disputeIndex].status = inFavorOfWorker ? .resolvedForWorker : .resolvedForEmployer
        shiftDisputes[disputeIndex].resolvedAt = Date()
        shiftDisputes[disputeIndex].resolutionNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if inFavorOfWorker {
            applications[applicationIndex].progressStatus = .paid
            updatePayoutRecordStatus(
                applicationId: applications[applicationIndex].id,
                status: .paid,
                note: "Спір вирішено на користь працівника"
            )
        } else if applications[applicationIndex].progressStatus == .inProgress {
            applications[applicationIndex].progressStatus = .completed
            updatePayoutRecordStatus(
                applicationId: applications[applicationIndex].id,
                status: .canceled,
                note: "Спір вирішено на користь роботодавця"
            )
        }
        appendDisputeUpdate(
            disputeId: shiftDisputes[disputeIndex].id,
            actorUserId: currentUser.id,
            actorTitle: "Роботодавець",
            message: "Кейс закрито: \(shiftDisputes[disputeIndex].status.title)"
        )

        appendExecutionEvent(
            shiftId: shiftDisputes[disputeIndex].shiftId,
            applicationId: shiftDisputes[disputeIndex].applicationId,
            actorUserId: currentUser.id,
            type: .disputeResolved,
            note: shiftDisputes[disputeIndex].status.title,
            coordinate: nil
        )

        let workerId = applications[applicationIndex].workerId
        addInAppNotification(
            for: workerId,
            title: "Спір вирішено",
            message: "По зміні «\(shift.title)» прийнято рішення: \(shiftDisputes[disputeIndex].status.title.lowercased()).",
            kind: inFavorOfWorker ? .success : .info
        )
        refreshReliability(for: applications[applicationIndex])
        return true
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

    func paymentBreakdown(for shift: JobShift, workersCount: Int = 1) -> ShiftPaymentBreakdown {
        let normalizedWorkers = max(1, workersCount)
        let gross = shift.pay * shift.durationHours * normalizedWorkers
        let workerFee = Int((Double(gross) * workerServiceFeeRate).rounded())
        let employerFee = Int((Double(gross) * employerServiceFeeRate).rounded())
        return ShiftPaymentBreakdown(
            grossAmount: gross,
            workerServiceFee: workerFee,
            workerNetAmount: max(0, gross - workerFee),
            employerServiceFee: employerFee,
            employerTotalAmount: gross + employerFee
        )
    }

    func acceptedApplicationsCount(for shiftId: UUID) -> Int {
        applications.filter { $0.shiftId == shiftId && $0.status == .accepted }.count
    }

    func pendingPayoutsForCurrentEmployer() -> [PayoutRecord] {
        guard let currentUser, currentUser.role == .employer else { return [] }
        return payoutRecords
            .filter { $0.employerId == currentUser.id && $0.status == .pendingRelease }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func releasePendingPayoutsForCurrentEmployer(limit: Int? = nil) -> Int {
        guard let currentUser, currentUser.role == .employer else { return 0 }
        let pending = pendingPayoutsForCurrentEmployer()
        guard !pending.isEmpty else { return 0 }

        let target = limit.map { Array(pending.prefix(max(0, $0))) } ?? pending
        var released = 0
        for payout in target {
            if let dispute = activeDispute(for: payout.applicationId),
               dispute.status == .open || dispute.status == .inReview {
                continue
            }
            guard let appIndex = applications.firstIndex(where: { $0.id == payout.applicationId }),
                  applications[appIndex].status == .accepted else { continue }

            applications[appIndex].progressStatus = .paid
            updatePayoutRecordStatus(
                applicationId: payout.applicationId,
                status: .paid,
                note: "Batch payout release роботодавцем"
            )
            if let shift = shift(by: applications[appIndex].shiftId) {
                addInAppNotification(
                    for: applications[appIndex].workerId,
                    title: "Виплату проведено",
                    message: "По зміні «\(shift.title)» виплату перераховано.",
                    kind: .success
                )
            }
            refreshReliability(for: applications[appIndex])
            released += 1
        }
        if released > 0 {
            addInAppNotification(
                for: currentUser.id,
                title: "Batch payout виконано",
                message: "Проведено виплат: \(released).",
                kind: .success
            )
        }
        return released
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

    func addReview(to userId: UUID, for shiftId: UUID, stars: Int, comment: String) -> Bool {
        guard let currentUser, currentUser.id != userId else { return false }
        guard canLeaveReview(from: currentUser.id, to: userId, for: shiftId) else {
            authErrorMessage = "Відгук можна залишити лише після завершеної співпраці"
            return false
        }
        guard !hasReview(from: currentUser.id, to: userId, for: shiftId) else {
            authErrorMessage = "Ви вже залишили відгук за цю зміну"
            return false
        }

        let clampedStars = min(5, max(1, stars))
        reviews.append(
            Review(
                id: UUID(),
                fromUserId: currentUser.id,
                toUserId: userId,
                shiftId: shiftId,
                stars: clampedStars,
                comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
                date: Date()
            )
        )
        recalculateRating(for: userId)
        authErrorMessage = nil
        return true
    }

    func canLeaveReview(from fromUserId: UUID, to toUserId: UUID, for shiftId: UUID, now: Date = Date()) -> Bool {
        guard let shift = shift(by: shiftId), shift.endDate <= now else { return false }
        let accepted = applications.filter { $0.shiftId == shiftId && $0.status == .accepted }
        guard !accepted.isEmpty else { return false }

        let fromIsEmployer = fromUserId == shift.employerId
        let toIsEmployer = toUserId == shift.employerId
        if fromIsEmployer == toIsEmployer { return false }

        if fromIsEmployer {
            return accepted.contains(where: { $0.workerId == toUserId })
        } else {
            return accepted.contains(where: { $0.workerId == fromUserId }) && toIsEmployer
        }
    }

    func hasReview(from fromUserId: UUID, to toUserId: UUID, for shiftId: UUID) -> Bool {
        reviews.contains {
            $0.fromUserId == fromUserId &&
            $0.toUserId == toUserId &&
            $0.shiftId == shiftId
        }
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

    private func applyAcceptedOffer(offer: DealOffer, responderId: UUID) {
        guard let shiftIndex = shifts.firstIndex(where: { $0.id == offer.shiftId }) else { return }
        guard let convo = conversations.first(where: { $0.id == offer.conversationId }) else { return }

        shifts[shiftIndex].pay = offer.proposedPayPerHour
        shifts[shiftIndex].startDate = offer.proposedStartDate
        shifts[shiftIndex].endDate = offer.proposedEndDate
        shifts[shiftIndex].address = offer.proposedAddress
        shifts[shiftIndex].requiredWorkers = max(1, offer.proposedWorkersCount)

        let workerId = convo.workerId
        let applicationId: UUID
        if let existingIndex = applications.firstIndex(where: { $0.shiftId == offer.shiftId && $0.workerId == workerId }) {
            applicationId = applications[existingIndex].id
            applications[existingIndex].status = .pending
            applications[existingIndex].progressStatus = .scheduled
            reminderTimestamps[applications[existingIndex].id] = nil
        } else {
            let now = Date()
            let createdId = UUID()
            applications.append(
                ShiftApplication(
                    id: createdId,
                    shiftId: offer.shiftId,
                    workerId: workerId,
                    status: .pending,
                    progressStatus: .scheduled,
                    createdAt: now,
                    respondBy: now
                )
            )
            applicationId = createdId
        }
        updateApplicationStatus(applicationId: applicationId, status: .accepted)
        guard applications.contains(where: { $0.id == applicationId && $0.status == .accepted }) else { return }

        // Cancel other pending offers for the same shift after agreement.
        for index in dealOffers.indices where dealOffers[index].shiftId == offer.shiftId && dealOffers[index].status == .pending && dealOffers[index].id != offer.id {
            dealOffers[index].status = .canceled
            dealOffers[index].respondedAt = Date()
        }

        syncShiftCapacity(for: offer.shiftId)

        if let convoIndex = conversations.firstIndex(where: { $0.id == offer.conversationId }) {
            let actorName = user(by: responderId)?.name ?? "Учасник"
            let stamp = Date()
            chatMessages.append(
                ChatMessage(
                    id: UUID(),
                    conversationId: offer.conversationId,
                    shiftId: offer.shiftId,
                    senderId: nil,
                    senderRole: .system,
                    text: "\(actorName) підтвердив(ла) оффер. Умови зафіксовано.",
                    createdAt: stamp,
                    isEdited: false,
                    offerId: offer.id
                )
            )
            conversations[convoIndex].lastMessageAt = stamp
        }
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
                self?.expireOverdueDisputes()
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

    private func expireOverdueDisputes(now: Date = Date()) {
        for index in shiftDisputes.indices {
            switch shiftDisputes[index].status {
            case .open:
                if shiftDisputes[index].slaDueAt <= now {
                    shiftDisputes[index].status = .inReview
                    shiftDisputes[index].escalatedAt = now
                    appendDisputeUpdate(
                        disputeId: shiftDisputes[index].id,
                        actorUserId: nil,
                        actorTitle: "Підтримка",
                        message: "Кейс автоматично ескаловано через SLA"
                    )
                    if let shift = shift(by: shiftDisputes[index].shiftId),
                       let application = applications.first(where: { $0.id == shiftDisputes[index].applicationId }) {
                        addInAppNotification(
                            for: application.workerId,
                            title: "Спір ескаловано",
                            message: "Підтримка підключилась до спору по зміні «\(shift.title)».",
                            kind: .warning
                        )
                        addInAppNotification(
                            for: shift.employerId,
                            title: "Спір ескаловано",
                            message: "По зміні «\(shift.title)» спір переведено на розгляд підтримки.",
                            kind: .warning
                        )
                    }
                }
            case .inReview:
                if let escalatedAt = shiftDisputes[index].escalatedAt,
                   now.timeIntervalSince(escalatedAt) >= Double(disputeAutoResolutionHours * 3600) {
                    autoResolveDispute(at: index, now: now)
                }
            case .resolvedForWorker, .resolvedForEmployer:
                break
            }
        }
    }

    private func autoResolveDispute(at index: Int, now: Date) {
        guard shiftDisputes.indices.contains(index),
              let shift = shift(by: shiftDisputes[index].shiftId),
              let appIndex = applications.firstIndex(where: { $0.id == shiftDisputes[index].applicationId }) else { return }

        let inFavorOfWorker = applications[appIndex].progressStatus == .completed || applications[appIndex].progressStatus == .paid || shift.endDate <= now
        shiftDisputes[index].status = inFavorOfWorker ? .resolvedForWorker : .resolvedForEmployer
        shiftDisputes[index].resolvedAt = now
        shiftDisputes[index].resolutionNote = "Автоматичне рішення через SLA підтримки"

        if inFavorOfWorker {
            applications[appIndex].progressStatus = .paid
            updatePayoutRecordStatus(
                applicationId: applications[appIndex].id,
                status: .paid,
                note: "Автовирішення спору на користь працівника"
            )
        } else {
            updatePayoutRecordStatus(
                applicationId: applications[appIndex].id,
                status: .canceled,
                note: "Автовирішення спору на користь роботодавця"
            )
        }

        appendExecutionEvent(
            shiftId: shiftDisputes[index].shiftId,
            applicationId: shiftDisputes[index].applicationId,
            actorUserId: shift.employerId,
            type: .disputeResolved,
            note: "Автовирішення: \(shiftDisputes[index].status.title)",
            coordinate: nil
        )
        appendDisputeUpdate(
            disputeId: shiftDisputes[index].id,
            actorUserId: nil,
            actorTitle: "Підтримка",
            message: "Кейс закрито автоматично: \(shiftDisputes[index].status.title)"
        )

        addInAppNotification(
            for: applications[appIndex].workerId,
            title: "Спір вирішено автоматично",
            message: "По зміні «\(shift.title)» зафіксовано рішення: \(shiftDisputes[index].status.title.lowercased()).",
            kind: inFavorOfWorker ? .success : .info
        )
        addInAppNotification(
            for: shift.employerId,
            title: "Спір закрито",
            message: "Автоматичне закриття спору по зміні «\(shift.title)».",
            kind: .info
        )
        refreshReliability(for: applications[appIndex], now: now)
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

    private func recalculateReliability(for userId: UUID, now: Date = Date()) {
        guard let userIndex = users.firstIndex(where: { $0.id == userId }) else { return }
        let user = users[userIndex]

        let userApps: [ShiftApplication]
        switch user.role {
        case .worker:
            userApps = applications.filter { $0.workerId == user.id && $0.status == .accepted }
        case .employer:
            let myShiftIds = Set(shifts.filter { $0.employerId == user.id }.map(\.id))
            userApps = applications.filter { myShiftIds.contains($0.shiftId) && $0.status == .accepted }
        }

        let total = userApps.count
        guard total > 0 else {
            users[userIndex].reliabilityScore = 0
            users[userIndex].completionRate = 0
            users[userIndex].cancelRate = 0
            users[userIndex].noShowRate = 0
            if currentUser?.id == user.id { currentUser = users[userIndex] }
            return
        }

        var completed = 0
        var canceled = 0
        var noShow = 0

        for app in userApps {
            guard let shift = shift(by: app.shiftId) else { continue }
            let isCompleted = app.progressStatus == .completed || app.progressStatus == .paid
            if isCompleted {
                completed += 1
                continue
            }

            if shift.endDate < now {
                if app.progressStatus == .scheduled {
                    noShow += 1
                } else if app.progressStatus == .inProgress {
                    canceled += 1
                }
            }
        }

        let completionRate = Double(completed) / Double(total)
        let cancelRate = Double(canceled) / Double(total)
        let noShowRate = Double(noShow) / Double(total)

        let score = (completionRate * 100.0) - (cancelRate * 35.0) - (noShowRate * 55.0)
        users[userIndex].completionRate = completionRate
        users[userIndex].cancelRate = cancelRate
        users[userIndex].noShowRate = noShowRate
        users[userIndex].reliabilityScore = min(100, max(0, score))

        if currentUser?.id == user.id {
            currentUser = users[userIndex]
        }
    }

    private func recalculateReliabilityForAll(now: Date = Date()) {
        for user in users {
            recalculateReliability(for: user.id, now: now)
        }
    }

    private func refreshReliability(for application: ShiftApplication, now: Date = Date()) {
        recalculateReliability(for: application.workerId, now: now)
        if let shift = shift(by: application.shiftId) {
            recalculateReliability(for: shift.employerId, now: now)
        }
        if let worker = user(by: application.workerId), worker.noShowRate >= 0.35 {
            registerRiskSignal(
                userId: worker.id,
                type: .highNoShow,
                level: .high,
                message: "Підвищений no-show rate: \(Int((worker.noShowRate * 100).rounded()))%",
                dedupHours: 24,
                now: now
            )
        }
    }

    private func latestNoShowDate(for workerId: UUID, now: Date) -> Date? {
        applications
            .filter { $0.workerId == workerId && $0.status == .accepted && $0.progressStatus == .scheduled }
            .compactMap { app -> Date? in
                guard let shift = shift(by: app.shiftId), shift.endDate < now else { return nil }
                return shift.endDate
            }
            .max()
    }

    private func detectExcessiveDisputesRisk(for userId: UUID, now: Date) {
        let from = now.addingTimeInterval(-7 * 24 * 3600)
        let count = shiftDisputes.filter { $0.openedByUserId == userId && $0.openedAt >= from }.count
        if count >= 4 {
            registerRiskSignal(
                userId: userId,
                type: .excessiveDisputes,
                level: .medium,
                message: "Часті спори за останні 7 днів (\(count))",
                dedupHours: 12,
                now: now
            )
        }
    }

    private func analyzeMessageRisk(senderId: UUID, text: String, at now: Date) {
        let lowered = text.lowercased()
        let hasPhone = lowered.range(of: #"(\+?\d[\d\-\s\(\)]{8,})"#, options: .regularExpression) != nil
        let hasEmail = lowered.range(of: #"[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}"#, options: .regularExpression) != nil
        let hasOffPlatformKeywords = ["telegram", "t.me", "viber", "whatsapp", "вайбер", "телеграм", "tg @"].contains { lowered.contains($0) }
        let hasLinks = lowered.contains("http://") || lowered.contains("https://") || lowered.contains("bit.ly")
        let hasExternalContact = hasPhone || hasEmail || hasOffPlatformKeywords || hasLinks

        if hasExternalContact {
            registerRiskSignal(
                userId: senderId,
                type: .offPlatformContactAttempt,
                level: .medium,
                message: "Спроба обміну зовнішніми контактами в чаті",
                dedupHours: 12,
                now: now
            )
            addInAppNotification(
                for: senderId,
                title: "Попередження безпеки",
                message: "Не передавайте контакти/оплату поза платформою до завершення угоди.",
                kind: .warning
            )
        }

        let recentOwnMessages = chatMessages.filter {
            $0.senderId == senderId &&
            $0.senderRole == .user &&
            now.timeIntervalSince($0.createdAt) <= 60
        }
        if recentOwnMessages.count >= 7 {
            registerRiskSignal(
                userId: senderId,
                type: .repeatedSpam,
                level: .low,
                message: "Підозра на спам-активність у чаті",
                dedupHours: 6,
                now: now
            )
        }
    }

    private func registerRiskSignal(
        userId: UUID,
        type: RiskSignalType,
        level: RiskLevel,
        message: String,
        dedupHours: Int,
        now: Date
    ) {
        if let recent = riskSignals.first(where: {
            $0.userId == userId &&
            $0.type == type &&
            now.timeIntervalSince($0.createdAt) <= Double(dedupHours * 3600)
        }) {
            _ = recent
            return
        }

        riskSignals.append(
            RiskSignal(
                id: UUID(),
                userId: userId,
                type: type,
                level: level,
                message: message,
                createdAt: now
            )
        )
        recordAuditEvent(
            userId: userId,
            actorUserId: nil,
            type: .risk,
            title: "Risk signal: \(type.rawValue)",
            message: message,
            relatedId: nil
        )
    }

    private func appendExecutionEvent(
        shiftId: UUID,
        applicationId: UUID,
        actorUserId: UUID,
        type: ShiftExecutionEventType,
        note: String,
        coordinate: CLLocationCoordinate2D?
    ) {
        shiftExecutionEvents.append(
            ShiftExecutionEvent(
                id: UUID(),
                shiftId: shiftId,
                applicationId: applicationId,
                actorUserId: actorUserId,
                type: type,
                createdAt: Date(),
                note: note,
                coordinate: coordinate
            )
        )
    }

    private func appendDisputeUpdate(
        disputeId: UUID,
        actorUserId: UUID?,
        actorTitle: String,
        message: String
    ) {
        disputeUpdates.append(
            DisputeUpdate(
                id: UUID(),
                disputeId: disputeId,
                actorUserId: actorUserId,
                actorTitle: actorTitle,
                message: message,
                createdAt: Date()
            )
        )
    }

    private func ensurePayoutRecord(for application: ShiftApplication) {
        guard payoutRecord(for: application.id) == nil,
              let shift = shift(by: application.shiftId) else { return }

        let breakdown = paymentBreakdown(for: shift, workersCount: 1)
        let created = PayoutRecord(
            id: UUID(),
            shiftId: shift.id,
            applicationId: application.id,
            workerId: application.workerId,
            employerId: shift.employerId,
            grossAmount: breakdown.grossAmount,
            workerNetAmount: breakdown.workerNetAmount,
            employerTotalAmount: breakdown.employerTotalAmount,
            status: .reserved,
            createdAt: Date(),
            updatedAt: Date(),
            note: "Створено payout запис"
        )
        payoutRecords.append(created)
        recordWalletTransaction(
            employerId: created.employerId,
            payoutRecordId: created.id,
            applicationId: created.applicationId,
            type: .reserve,
            amount: created.employerTotalAmount,
            note: "Кошти зарезервовано під зміну"
        )
        persistWalletState()
    }

    private func updatePayoutRecordStatus(applicationId: UUID, status: PayoutStatus, note: String) {
        guard let index = payoutRecords.firstIndex(where: { $0.applicationId == applicationId }) else { return }
        let oldStatus = payoutRecords[index].status
        payoutRecords[index].status = status
        payoutRecords[index].updatedAt = Date()
        payoutRecords[index].note = note
        applyWalletEffectForPayoutTransition(record: payoutRecords[index], from: oldStatus, to: status, note: note)
        persistWalletState()
    }

    private func isEscrowReserved(_ status: PayoutStatus) -> Bool {
        switch status {
        case .reserved, .onHold, .pendingRelease:
            return true
        case .paid, .canceled:
            return false
        }
    }

    private func applyWalletEffectForPayoutTransition(record: PayoutRecord, from oldStatus: PayoutStatus, to newStatus: PayoutStatus, note: String) {
        guard oldStatus != newStatus else { return }

        if isEscrowReserved(oldStatus) == false && isEscrowReserved(newStatus) == true {
            recordWalletTransaction(
                employerId: record.employerId,
                payoutRecordId: record.id,
                applicationId: record.applicationId,
                type: .reserve,
                amount: record.employerTotalAmount,
                note: note
            )
        }

        if isEscrowReserved(oldStatus) == true && isEscrowReserved(newStatus) == false {
            recordWalletTransaction(
                employerId: record.employerId,
                payoutRecordId: record.id,
                applicationId: record.applicationId,
                type: .release,
                amount: record.employerTotalAmount,
                note: note
            )
        }

        if oldStatus != .paid && newStatus == .paid {
            walletBalances[record.employerId, default: employerInitialDemoBalance] -= record.employerTotalAmount
            recordWalletTransaction(
                employerId: record.employerId,
                payoutRecordId: record.id,
                applicationId: record.applicationId,
                type: .payout,
                amount: -record.employerTotalAmount,
                note: note
            )
        } else if oldStatus == .paid && newStatus != .paid {
            walletBalances[record.employerId, default: employerInitialDemoBalance] += record.employerTotalAmount
            recordWalletTransaction(
                employerId: record.employerId,
                payoutRecordId: record.id,
                applicationId: record.applicationId,
                type: .refund,
                amount: record.employerTotalAmount,
                note: note
            )
        }
    }

    private func recordWalletTransaction(
        employerId: UUID,
        payoutRecordId: UUID?,
        applicationId: UUID?,
        type: WalletTransactionType,
        amount: Int,
        note: String
    ) {
        walletTransactions.append(
            WalletTransaction(
                id: UUID(),
                employerId: employerId,
                payoutRecordId: payoutRecordId,
                applicationId: applicationId,
                type: type,
                amount: amount,
                note: note,
                createdAt: Date()
            )
        )
        recordAuditEvent(
            userId: employerId,
            actorUserId: currentUser?.id,
            type: .escrow,
            title: type.title,
            message: "\(note) (\(amount) грн)",
            relatedId: payoutRecordId ?? applicationId
        )
    }

    private func ensurePayoutRecordsForAcceptedApplications() {
        for application in applications where application.status == .accepted {
            ensurePayoutRecord(for: application)
            let targetStatus: PayoutStatus
            switch application.progressStatus {
            case .scheduled, .inProgress:
                targetStatus = .reserved
            case .completed:
                targetStatus = activeDispute(for: application.id) == nil ? .pendingRelease : .onHold
            case .paid:
                targetStatus = .paid
            }
            updatePayoutRecordStatus(
                applicationId: application.id,
                status: targetStatus,
                note: "Синхронізація payout стану"
            )
        }
    }

    private func addInAppNotification(for userId: UUID, title: String, message: String, kind: NotificationKind) {
        let now = Date()
        let key = "\(userId.uuidString)|\(title)|\(kind.rawValue)"
        if let last = lastNotificationTimestampsByKey[key],
           now.timeIntervalSince(last) < Double(notificationDedupSeconds) {
            return
        }
        lastNotificationTimestampsByKey[key] = now
        notifications.append(
            InAppNotification(
                id: UUID(),
                userId: userId,
                title: title,
                message: message,
                kind: kind,
                createdAt: now,
                isRead: false
            )
        )
    }

    private func recordAuditEvent(
        userId: UUID?,
        actorUserId: UUID?,
        type: AuditEventType,
        title: String,
        message: String,
        relatedId: UUID?
    ) {
        auditEvents.append(
            AuditEvent(
                id: UUID(),
                userId: userId,
                actorUserId: actorUserId,
                type: type,
                title: title,
                message: message,
                relatedId: relatedId,
                createdAt: Date()
            )
        )
        if auditEvents.count > 1500 {
            auditEvents = Array(auditEvents.suffix(1200))
        }
        persistAuditState()
    }

    private func recordModerationAction(
        caseId: UUID,
        actorUserId: UUID?,
        assignedModeratorId: UUID?,
        type: ModerationCaseActionType,
        note: String
    ) {
        moderationActions.append(
            ModerationCaseAction(
                id: UUID(),
                caseId: caseId,
                actorUserId: actorUserId,
                assignedModeratorId: assignedModeratorId,
                type: type,
                note: note,
                createdAt: Date()
            )
        )
        if moderationActions.count > 1800 {
            moderationActions = Array(moderationActions.suffix(1200))
        }
        persistModerationActionsState()
    }

    private func createOrRefreshModerationCase(
        userId: UUID,
        type: ModerationCaseType,
        subject: String,
        details: String,
        status: ModerationCaseStatus
    ) {
        let now = Date()
        let relatedCaseId: UUID
        if let idx = moderationCases.firstIndex(where: {
            $0.userId == userId && $0.type == type && ($0.status == .open || $0.status == .inReview)
        }) {
            moderationCases[idx].subject = subject
            moderationCases[idx].details = details
            moderationCases[idx].status = status
            moderationCases[idx].updatedAt = now
            moderationCases[idx].resolutionNote = ""
            if status == .open {
                moderationCases[idx].assignedModeratorId = nil
            }
            relatedCaseId = moderationCases[idx].id
        } else {
            let id = UUID()
            moderationCases.append(
                ModerationCase(
                    id: id,
                    userId: userId,
                    type: type,
                    status: status,
                    subject: subject,
                    details: details,
                    createdAt: now,
                    updatedAt: now,
                    resolutionNote: "",
                    assignedModeratorId: nil
                )
            )
            relatedCaseId = id
            recordModerationAction(
                caseId: id,
                actorUserId: currentUser?.id,
                assignedModeratorId: nil,
                type: .created,
                note: subject
            )
        }
        recordAuditEvent(
            userId: userId,
            actorUserId: currentUser?.id,
            type: .moderation,
            title: "\(type.title): \(status.title)",
            message: subject,
            relatedId: relatedCaseId
        )
    }

    private func reduceRiskSignals(for userId: UUID, note: String) {
        let cutoff = Date().addingTimeInterval(-14 * 24 * 3600)
        var removed = 0
        riskSignals.removeAll { signal in
            guard signal.userId == userId else { return false }
            if signal.createdAt >= cutoff && signal.level != .low && removed < 2 {
                removed += 1
                return true
            }
            return false
        }
        if removed == 0 {
            registerRiskSignal(
                userId: userId,
                type: .repeatedSpam,
                level: .low,
                message: "Апеляцію прийнято: \(note)",
                dedupHours: 1,
                now: Date()
            )
        }
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
        let reliabilityScore: Double?
        let completionRate: Double?
        let cancelRate: Double?
        let noShowRate: Double?
        let employerKYCStatus: String?
        let employerCompanyName: String?
        let employerTaxId: String?
        let kycReviewNote: String?
        let moderationRole: String?
    }

    private struct PersistedWallet: Codable {
        let employerId: UUID
        let balance: Int
    }

    private struct PersistedWalletTransaction: Codable {
        let id: UUID
        let employerId: UUID
        let payoutRecordId: UUID?
        let applicationId: UUID?
        let type: String
        let amount: Int
        let note: String
        let createdAt: Date
    }

    private struct PersistedModerationCase: Codable {
        let id: UUID
        let userId: UUID
        let type: String
        let status: String
        let subject: String
        let details: String
        let createdAt: Date
        let updatedAt: Date
        let resolutionNote: String
        let assignedModeratorId: UUID?
    }

    private struct PersistedModerationAction: Codable {
        let id: UUID
        let caseId: UUID
        let actorUserId: UUID?
        let assignedModeratorId: UUID?
        let type: String
        let note: String
        let createdAt: Date
    }

    private struct PersistedAuditEvent: Codable {
        let id: UUID
        let userId: UUID?
        let actorUserId: UUID?
        let type: String
        let title: String
        let message: String
        let relatedId: UUID?
        let createdAt: Date
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
                reviewsCount: $0.reviewsCount,
                reliabilityScore: $0.reliabilityScore,
                completionRate: $0.completionRate,
                cancelRate: $0.cancelRate,
                noShowRate: $0.noShowRate,
                employerKYCStatus: $0.employerKYCStatus.rawValue,
                employerCompanyName: $0.employerCompanyName,
                employerTaxId: $0.employerTaxId,
                kycReviewNote: $0.kycReviewNote,
                moderationRole: $0.moderationRole.rawValue
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
            let kycStatus = item.employerKYCStatus.flatMap { EmployerKYCStatus(rawValue: $0) } ?? .notSubmitted
            let moderationRole = item.moderationRole.flatMap { ModerationRole(rawValue: $0) } ?? .none
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
                reviewsCount: item.reviewsCount,
                reliabilityScore: item.reliabilityScore ?? 0,
                completionRate: item.completionRate ?? 0,
                cancelRate: item.cancelRate ?? 0,
                noShowRate: item.noShowRate ?? 0,
                employerKYCStatus: kycStatus,
                employerCompanyName: item.employerCompanyName ?? "",
                employerTaxId: item.employerTaxId ?? "",
                kycReviewNote: item.kycReviewNote ?? "",
                moderationRole: moderationRole
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

    private func ensureWalletsForEmployers() {
        let employerIds = users.filter { $0.role == .employer }.map(\.id)
        for employerId in employerIds where walletBalances[employerId] == nil {
            walletBalances[employerId] = employerInitialDemoBalance
            recordWalletTransaction(
                employerId: employerId,
                payoutRecordId: nil,
                applicationId: nil,
                type: .topUp,
                amount: employerInitialDemoBalance,
                note: "Стартовий демо-баланс"
            )
        }
        persistWalletState()
    }

    private func persistWalletState() {
        let walletsPayload = walletBalances.map { PersistedWallet(employerId: $0.key, balance: $0.value) }
        if let encodedWallets = try? JSONEncoder().encode(walletsPayload) {
            UserDefaults.standard.set(encodedWallets, forKey: walletBalancesStorageKey)
        }

        let txPayload = walletTransactions.map {
            PersistedWalletTransaction(
                id: $0.id,
                employerId: $0.employerId,
                payoutRecordId: $0.payoutRecordId,
                applicationId: $0.applicationId,
                type: $0.type.rawValue,
                amount: $0.amount,
                note: $0.note,
                createdAt: $0.createdAt
            )
        }
        if let encodedTx = try? JSONEncoder().encode(txPayload) {
            UserDefaults.standard.set(encodedTx, forKey: walletTransactionsStorageKey)
        }
    }

    private func loadWalletState() {
        if let data = UserDefaults.standard.data(forKey: walletBalancesStorageKey),
           let payload = try? JSONDecoder().decode([PersistedWallet].self, from: data) {
            walletBalances = Dictionary(uniqueKeysWithValues: payload.map { ($0.employerId, $0.balance) })
        } else {
            walletBalances = [:]
        }

        if let txData = UserDefaults.standard.data(forKey: walletTransactionsStorageKey),
           let txPayload = try? JSONDecoder().decode([PersistedWalletTransaction].self, from: txData) {
            walletTransactions = txPayload.compactMap { item in
                guard let type = WalletTransactionType(rawValue: item.type) else { return nil }
                return WalletTransaction(
                    id: item.id,
                    employerId: item.employerId,
                    payoutRecordId: item.payoutRecordId,
                    applicationId: item.applicationId,
                    type: type,
                    amount: item.amount,
                    note: item.note,
                    createdAt: item.createdAt
                )
            }
        } else {
            walletTransactions = []
        }
    }

    private func persistModerationState() {
        let payload = moderationCases.map {
            PersistedModerationCase(
                id: $0.id,
                userId: $0.userId,
                type: $0.type.rawValue,
                status: $0.status.rawValue,
                subject: $0.subject,
                details: $0.details,
                createdAt: $0.createdAt,
                updatedAt: $0.updatedAt,
                resolutionNote: $0.resolutionNote,
                assignedModeratorId: $0.assignedModeratorId
            )
        }
        if let encoded = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(encoded, forKey: moderationCasesStorageKey)
        }
    }

    private func loadModerationState() {
        if let data = UserDefaults.standard.data(forKey: moderationCasesStorageKey),
           let payload = try? JSONDecoder().decode([PersistedModerationCase].self, from: data) {
            moderationCases = payload.compactMap { item in
                guard let type = ModerationCaseType(rawValue: item.type),
                      let status = ModerationCaseStatus(rawValue: item.status) else { return nil }
                return ModerationCase(
                    id: item.id,
                    userId: item.userId,
                    type: type,
                    status: status,
                    subject: item.subject,
                    details: item.details,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    resolutionNote: item.resolutionNote,
                    assignedModeratorId: item.assignedModeratorId
                )
            }
        } else {
            moderationCases = []
        }
    }

    private func persistModerationActionsState() {
        let payload = moderationActions.map {
            PersistedModerationAction(
                id: $0.id,
                caseId: $0.caseId,
                actorUserId: $0.actorUserId,
                assignedModeratorId: $0.assignedModeratorId,
                type: $0.type.rawValue,
                note: $0.note,
                createdAt: $0.createdAt
            )
        }
        if let encoded = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(encoded, forKey: moderationActionsStorageKey)
        }
    }

    private func loadModerationActionsState() {
        if let data = UserDefaults.standard.data(forKey: moderationActionsStorageKey),
           let payload = try? JSONDecoder().decode([PersistedModerationAction].self, from: data) {
            moderationActions = payload.compactMap { item in
                guard let type = ModerationCaseActionType(rawValue: item.type) else { return nil }
                return ModerationCaseAction(
                    id: item.id,
                    caseId: item.caseId,
                    actorUserId: item.actorUserId,
                    assignedModeratorId: item.assignedModeratorId,
                    type: type,
                    note: item.note,
                    createdAt: item.createdAt
                )
            }
        } else {
            moderationActions = []
        }
    }

    private func persistAuditState() {
        let payload = auditEvents.map {
            PersistedAuditEvent(
                id: $0.id,
                userId: $0.userId,
                actorUserId: $0.actorUserId,
                type: $0.type.rawValue,
                title: $0.title,
                message: $0.message,
                relatedId: $0.relatedId,
                createdAt: $0.createdAt
            )
        }
        if let encoded = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(encoded, forKey: auditEventsStorageKey)
        }
    }

    private func loadAuditState() {
        if let data = UserDefaults.standard.data(forKey: auditEventsStorageKey),
           let payload = try? JSONDecoder().decode([PersistedAuditEvent].self, from: data) {
            auditEvents = payload.compactMap { item in
                guard let type = AuditEventType(rawValue: item.type) else { return nil }
                return AuditEvent(
                    id: item.id,
                    userId: item.userId,
                    actorUserId: item.actorUserId,
                    type: type,
                    title: item.title,
                    message: item.message,
                    relatedId: item.relatedId,
                    createdAt: item.createdAt
                )
            }
        } else {
            auditEvents = []
        }
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

        applications = buildDemoApplications(shifts: shifts, worker1: worker1, worker2: worker2, now: now)
        let demoCommunication = buildDemoCommunication(shifts: shifts, applications: applications, now: now)
        conversations = demoCommunication.conversations
        chatMessages = demoCommunication.messages
        dealOffers = demoCommunication.offers

        for shift in shifts {
            syncShiftCapacity(for: shift.id)
        }
        recalculateReliabilityForAll(now: now)
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
            reviewsCount: 0,
            reliabilityScore: 0,
            completionRate: 0,
            cancelRate: 0,
            noShowRate: 0,
            moderationRole: .lead
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
            reviewsCount: 0,
            reliabilityScore: 0,
            completionRate: 0,
            cancelRate: 0,
            noShowRate: 0,
            moderationRole: .agent
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
            reviewsCount: 0,
            reliabilityScore: 0,
            completionRate: 0,
            cancelRate: 0,
            noShowRate: 0
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
            reviewsCount: 0,
            reliabilityScore: 0,
            completionRate: 0,
            cancelRate: 0,
            noShowRate: 0
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

        applications = buildDemoApplications(shifts: shifts, worker1: worker1, worker2: worker2, now: now)
        let demoCommunication = buildDemoCommunication(shifts: shifts, applications: applications, now: now)
        conversations = demoCommunication.conversations
        chatMessages = demoCommunication.messages
        dealOffers = demoCommunication.offers

        for shift in shifts {
            syncShiftCapacity(for: shift.id)
        }
        recalculateReliabilityForAll(now: now)
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

        // Make a part of shifts completed/past to test completed activity flows.
        for index in demoShifts.indices.prefix(10) {
            let duration = demoShifts[index].endDate.timeIntervalSince(demoShifts[index].startDate)
            let newStart = calendar.date(byAdding: .day, value: -(index + 2), to: now) ?? now
            demoShifts[index].startDate = newStart
            demoShifts[index].endDate = newStart.addingTimeInterval(max(3600, duration))
        }

        return demoShifts
    }

    private func buildDemoApplications(shifts: [JobShift], worker1: AppUser, worker2: AppUser, now: Date) -> [ShiftApplication] {
        guard !shifts.isEmpty else { return [] }
        var items: [ShiftApplication] = []

        for (index, shift) in shifts.prefix(50).enumerated() {
            let primaryWorker = index.isMultiple(of: 2) ? worker1 : worker2
            let primaryStatus: ApplicationStatus
            if index % 6 == 0 {
                primaryStatus = .pending
            } else if index % 9 == 0 {
                primaryStatus = .rejected
            } else {
                primaryStatus = .accepted
            }

            let primaryCreatedAt = Calendar.current.date(byAdding: .hour, value: -(index * 2), to: now) ?? now
            let primaryRespondBy = Calendar.current.date(byAdding: .hour, value: employerResponseSLAHours, to: primaryCreatedAt) ?? primaryCreatedAt
            items.append(
                ShiftApplication(
                    id: UUID(),
                    shiftId: shift.id,
                    workerId: primaryWorker.id,
                    status: primaryStatus,
                    progressStatus: primaryStatus == .accepted ? demoProgressStatus(for: shift, index: index) : .scheduled,
                    createdAt: primaryCreatedAt,
                    respondBy: primaryRespondBy
                )
            )

            let secondaryWorker = primaryWorker.id == worker1.id ? worker2 : worker1
            let secondaryStatus: ApplicationStatus
            if index % 8 == 0 {
                secondaryStatus = .pending
            } else if index % 5 == 0 || shift.endDate <= now {
                secondaryStatus = .accepted
            } else {
                secondaryStatus = .rejected
            }

            let secondaryCreatedAt = Calendar.current.date(byAdding: .hour, value: -((index * 2) + 1), to: now) ?? now
            let secondaryRespondBy = Calendar.current.date(byAdding: .hour, value: employerResponseSLAHours, to: secondaryCreatedAt) ?? secondaryCreatedAt
            items.append(
                ShiftApplication(
                    id: UUID(),
                    shiftId: shift.id,
                    workerId: secondaryWorker.id,
                    status: secondaryStatus,
                    progressStatus: secondaryStatus == .accepted ? demoProgressStatus(for: shift, index: index + 1) : .scheduled,
                    createdAt: secondaryCreatedAt,
                    respondBy: secondaryRespondBy
                )
            )
        }

        return items
    }

    private func demoProgressStatus(for shift: JobShift, index: Int) -> WorkProgressStatus {
        if shift.endDate <= Date() {
            return index.isMultiple(of: 2) ? .paid : .completed
        }
        if shift.startDate <= Date() {
            return .inProgress
        }
        return .scheduled
    }

    private func buildDemoCommunication(
        shifts: [JobShift],
        applications: [ShiftApplication],
        now: Date
    ) -> (conversations: [ShiftConversation], messages: [ChatMessage], offers: [DealOffer]) {
        var resultConversations: [ShiftConversation] = []
        var resultMessages: [ChatMessage] = []
        var resultOffers: [DealOffer] = []

        let acceptedApps = applications
            .filter { $0.status == .accepted }
            .prefix(18)

        for (index, application) in acceptedApps.enumerated() {
            guard let shift = shifts.first(where: { $0.id == application.shiftId }) else { continue }
            let created = Calendar.current.date(byAdding: .hour, value: -(index * 3 + 2), to: now) ?? now
            let convoId = UUID()

            let conversation = ShiftConversation(
                id: convoId,
                shiftId: shift.id,
                employerId: shift.employerId,
                workerId: application.workerId,
                createdAt: created,
                lastMessageAt: created,
                employerLastReadAt: created,
                workerLastReadAt: created
            )
            resultConversations.append(conversation)

            let offerStatus: DealOfferStatus = index % 4 == 0 ? .accepted : (index % 7 == 0 ? .rejected : .pending)
            let offer = DealOffer(
                id: UUID(),
                shiftId: shift.id,
                conversationId: convoId,
                fromUserId: shift.employerId,
                toUserId: application.workerId,
                proposedPayPerHour: shift.pay,
                proposedStartDate: shift.startDate,
                proposedEndDate: shift.endDate,
                proposedAddress: shift.address,
                proposedWorkersCount: shift.requiredWorkers,
                status: offerStatus,
                createdAt: created,
                respondedAt: offerStatus == .pending ? nil : Calendar.current.date(byAdding: .minute, value: 30, to: created)
            )
            resultOffers.append(offer)

            resultMessages.append(
                ChatMessage(
                    id: UUID(),
                    conversationId: convoId,
                    shiftId: shift.id,
                    senderId: nil,
                    senderRole: .system,
                    text: "Діалог створено для узгодження умов співпраці.",
                    createdAt: created,
                    isEdited: false,
                    offerId: nil
                )
            )
            resultMessages.append(
                ChatMessage(
                    id: UUID(),
                    conversationId: convoId,
                    shiftId: shift.id,
                    senderId: shift.employerId,
                    senderRole: .user,
                    text: "Вітаю! Перевірте, будь ласка, оффер нижче.",
                    createdAt: Calendar.current.date(byAdding: .minute, value: 8, to: created) ?? created,
                    isEdited: false,
                    offerId: nil
                )
            )
            resultMessages.append(
                ChatMessage(
                    id: UUID(),
                    conversationId: convoId,
                    shiftId: shift.id,
                    senderId: shift.employerId,
                    senderRole: .user,
                    text: "Надіслано оффер: \(shift.pay) грн/год.",
                    createdAt: Calendar.current.date(byAdding: .minute, value: 10, to: created) ?? created,
                    isEdited: false,
                    offerId: offer.id
                )
            )
            if offerStatus != .pending {
                resultMessages.append(
                    ChatMessage(
                        id: UUID(),
                        conversationId: convoId,
                        shiftId: shift.id,
                        senderId: application.workerId,
                        senderRole: .user,
                        text: offerStatus == .accepted ? "Оффер прийнято." : "Оффер відхилено.",
                        createdAt: Calendar.current.date(byAdding: .minute, value: 40, to: created) ?? created,
                        isEdited: false,
                        offerId: offer.id
                    )
                )
            }
        }

        for index in resultConversations.indices {
            let convo = resultConversations[index]
            let convoMessages = resultMessages.filter { $0.conversationId == convo.id }
            if let last = convoMessages.max(by: { $0.createdAt < $1.createdAt }) {
                resultConversations[index].lastMessageAt = last.createdAt
                resultConversations[index].employerLastReadAt = Calendar.current.date(byAdding: .minute, value: -5, to: last.createdAt) ?? last.createdAt
                resultConversations[index].workerLastReadAt = Calendar.current.date(byAdding: .minute, value: -3, to: last.createdAt) ?? last.createdAt
            }
        }

        return (
            conversations: resultConversations,
            messages: resultMessages.sorted { $0.createdAt < $1.createdAt },
            offers: resultOffers.sorted { $0.createdAt > $1.createdAt }
        )
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
