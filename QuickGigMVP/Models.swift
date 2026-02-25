import Foundation
import CoreLocation

enum UserRole: String, CaseIterable, Identifiable {
    case worker
    case employer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .worker:
            return "Працівник"
        case .employer:
            return "Роботодавець"
        }
    }
}

enum ShiftStatus: String, CaseIterable, Identifiable {
    case open
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open:
            return "Відкрита"
        case .closed:
            return "Закрита"
        }
    }
}

enum ApplicationStatus: String, CaseIterable, Identifiable {
    case pending
    case accepted
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending:
            return "Очікує"
        case .accepted:
            return "Прийнято"
        case .rejected:
            return "Відхилено"
        }
    }
}

enum WorkProgressStatus: String, CaseIterable, Identifiable {
    case scheduled
    case inProgress
    case completed
    case paid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduled:
            return "Заплановано"
        case .inProgress:
            return "В роботі"
        case .completed:
            return "Завершено"
        case .paid:
            return "Оплачено"
        }
    }
}

enum WorkFormat: String, CaseIterable, Identifiable {
    case offline
    case online

    var id: String { rawValue }

    var title: String {
        switch self {
        case .offline:
            return "Офлайн"
        case .online:
            return "Онлайн"
        }
    }
}

enum EmployerKYCStatus: String {
    case notSubmitted
    case pending
    case verified
    case rejected

    var title: String {
        switch self {
        case .notSubmitted:
            return "Не подано"
        case .pending:
            return "На перевірці"
        case .verified:
            return "Підтверджено"
        case .rejected:
            return "Відхилено"
        }
    }
}

enum ModerationRole: String, CaseIterable {
    case none
    case agent
    case lead

    var title: String {
        switch self {
        case .none:
            return "Немає"
        case .agent:
            return "Агент"
        case .lead:
            return "Лід"
        }
    }

    var canReviewCases: Bool {
        self == .agent || self == .lead
    }

    var canAssignCases: Bool {
        self == .lead
    }

    var canResolveAnyCase: Bool {
        self == .lead
    }
}

struct AppUser: Identifiable {
    let id: UUID
    var name: String
    var phone: String
    var isPhoneVerified: Bool
    var email: String
    var isEmailVerified: Bool
    var password: String
    var role: UserRole
    var resumeSummary: String
    var isVerifiedEmployer: Bool
    var rating: Double
    var reviewsCount: Int
    var reliabilityScore: Double
    var completionRate: Double
    var cancelRate: Double
    var noShowRate: Double
    var employerKYCStatus: EmployerKYCStatus = .notSubmitted
    var employerCompanyName: String = ""
    var employerTaxId: String = ""
    var kycReviewNote: String = ""
    var moderationRole: ModerationRole = .none

    var initials: String {
        let pieces = name.split(separator: " ")
        let letters = pieces.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "U" : String(letters)
    }
}

struct JobShift: Identifiable {
    let id: UUID
    var title: String
    var details: String
    var address: String
    var pay: Int
    var startDate: Date
    var endDate: Date
    var coordinate: CLLocationCoordinate2D
    var employerId: UUID
    var workFormat: WorkFormat
    var requiredWorkers: Int
    var status: ShiftStatus

    var durationHours: Int {
        let seconds = endDate.timeIntervalSince(startDate)
        return max(1, Int(seconds / 3600))
    }
}

struct ShiftApplication: Identifiable {
    let id: UUID
    let shiftId: UUID
    let workerId: UUID
    var status: ApplicationStatus
    var progressStatus: WorkProgressStatus
    let createdAt: Date
    let respondBy: Date
}

struct Review: Identifiable {
    let id: UUID
    let fromUserId: UUID
    let toUserId: UUID
    var shiftId: UUID? = nil
    let stars: Int
    let comment: String
    let date: Date
}

enum NotificationKind: String {
    case info
    case success
    case warning
    case error
}

struct InAppNotification: Identifiable {
    let id: UUID
    let userId: UUID
    let title: String
    let message: String
    let kind: NotificationKind
    let createdAt: Date
    var isRead: Bool
}

enum MessageSenderRole: String, Codable {
    case system
    case user
}

enum DealOfferStatus: String, CaseIterable, Identifiable, Codable {
    case pending
    case accepted
    case rejected
    case canceled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending:
            return "Очікує рішення"
        case .accepted:
            return "Прийнято"
        case .rejected:
            return "Відхилено"
        case .canceled:
            return "Скасовано"
        }
    }
}

struct DealOffer: Identifiable {
    let id: UUID
    let shiftId: UUID
    let conversationId: UUID
    let fromUserId: UUID
    let toUserId: UUID
    let proposedPayPerHour: Int
    let proposedStartDate: Date
    let proposedEndDate: Date
    let proposedAddress: String
    let proposedWorkersCount: Int
    var status: DealOfferStatus
    let createdAt: Date
    var respondedAt: Date?
}

struct ChatMessage: Identifiable {
    let id: UUID
    let conversationId: UUID
    let shiftId: UUID
    let senderId: UUID?
    let senderRole: MessageSenderRole
    let text: String
    let createdAt: Date
    var isEdited: Bool
    var offerId: UUID?
}

struct ShiftConversation: Identifiable {
    let id: UUID
    let shiftId: UUID
    let employerId: UUID
    let workerId: UUID
    let createdAt: Date
    var lastMessageAt: Date
    var employerLastReadAt: Date
    var workerLastReadAt: Date
}

struct ShiftPaymentBreakdown {
    let grossAmount: Int
    let workerServiceFee: Int
    let workerNetAmount: Int
    let employerServiceFee: Int
    let employerTotalAmount: Int
}

enum DisputeCategory: String, CaseIterable, Identifiable {
    case payment
    case attendance
    case quality
    case behavior
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .payment:
            return "Оплата"
        case .attendance:
            return "Вихід на зміну"
        case .quality:
            return "Якість виконання"
        case .behavior:
            return "Поведінка"
        case .other:
            return "Інше"
        }
    }
}

enum ShiftExecutionEventType: String {
    case checkIn
    case checkOut
    case disputeOpened
    case disputeResolved

    var title: String {
        switch self {
        case .checkIn:
            return "Check-in"
        case .checkOut:
            return "Check-out"
        case .disputeOpened:
            return "Відкрито спір"
        case .disputeResolved:
            return "Спір вирішено"
        }
    }
}

struct ShiftExecutionEvent: Identifiable {
    let id: UUID
    let shiftId: UUID
    let applicationId: UUID
    let actorUserId: UUID
    let type: ShiftExecutionEventType
    let createdAt: Date
    var note: String
    var coordinate: CLLocationCoordinate2D?
}

enum ShiftDisputeStatus: String {
    case open
    case inReview
    case resolvedForWorker
    case resolvedForEmployer

    var title: String {
        switch self {
        case .open:
            return "Відкрито"
        case .inReview:
            return "На розгляді"
        case .resolvedForWorker:
            return "Рішення на користь працівника"
        case .resolvedForEmployer:
            return "Рішення на користь роботодавця"
        }
    }
}

struct ShiftDispute: Identifiable {
    let id: UUID
    let shiftId: UUID
    let applicationId: UUID
    let openedByUserId: UUID
    let openedAt: Date
    let slaDueAt: Date
    let category: DisputeCategory
    let reason: String
    var status: ShiftDisputeStatus
    var escalatedAt: Date?
    var resolvedAt: Date?
    var resolutionNote: String?
}

struct DisputeUpdate: Identifiable {
    let id: UUID
    let disputeId: UUID
    let actorUserId: UUID?
    let actorTitle: String
    let message: String
    let createdAt: Date
}

enum PayoutStatus: String {
    case reserved
    case onHold
    case pendingRelease
    case paid
    case canceled

    var title: String {
        switch self {
        case .reserved:
            return "Резерв"
        case .onHold:
            return "На холді"
        case .pendingRelease:
            return "Готується виплата"
        case .paid:
            return "Виплачено"
        case .canceled:
            return "Скасовано"
        }
    }
}

struct PayoutRecord: Identifiable {
    let id: UUID
    let shiftId: UUID
    let applicationId: UUID
    let workerId: UUID
    let employerId: UUID
    let grossAmount: Int
    let workerNetAmount: Int
    let employerTotalAmount: Int
    var status: PayoutStatus
    let createdAt: Date
    var updatedAt: Date
    var note: String
}

enum WalletTransactionType: String {
    case topUp
    case reserve
    case release
    case payout
    case refund

    var title: String {
        switch self {
        case .topUp:
            return "Поповнення"
        case .reserve:
            return "Резерв ескроу"
        case .release:
            return "Зняття резерву"
        case .payout:
            return "Виплата працівнику"
        case .refund:
            return "Повернення коштів"
        }
    }
}

struct WalletTransaction: Identifiable {
    let id: UUID
    let employerId: UUID
    let payoutRecordId: UUID?
    let applicationId: UUID?
    let type: WalletTransactionType
    let amount: Int
    let note: String
    let createdAt: Date
}

struct EscrowReconciliationReport {
    let employerId: UUID
    let walletBalance: Int
    let reservedAmount: Int
    let pendingPayoutAmount: Int
    let paidAmount: Int
    let expectedAvailable: Int
    let actualAvailable: Int
    let mismatchAmount: Int
    let generatedAt: Date

    var isHealthy: Bool {
        mismatchAmount == 0 && walletBalance >= 0 && actualAvailable >= 0
    }
}

enum RiskLevel: String {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low:
            return "Низький"
        case .medium:
            return "Середній"
        case .high:
            return "Високий"
        }
    }
}

enum RiskSignalType: String {
    case offPlatformContactAttempt
    case excessiveDisputes
    case highNoShow
    case repeatedSpam
}

struct RiskSignal: Identifiable {
    let id: UUID
    let userId: UUID
    let type: RiskSignalType
    let level: RiskLevel
    let message: String
    let createdAt: Date
}

enum ModerationCaseType: String {
    case kyc
    case riskAppeal

    var title: String {
        switch self {
        case .kyc:
            return "KYC"
        case .riskAppeal:
            return "Risk appeal"
        }
    }
}

enum ModerationCaseStatus: String {
    case open
    case inReview
    case resolvedApproved
    case resolvedRejected

    var title: String {
        switch self {
        case .open:
            return "Відкрито"
        case .inReview:
            return "На розгляді"
        case .resolvedApproved:
            return "Підтверджено"
        case .resolvedRejected:
            return "Відхилено"
        }
    }
}

struct ModerationCase: Identifiable {
    let id: UUID
    let userId: UUID
    let type: ModerationCaseType
    var status: ModerationCaseStatus
    var subject: String
    var details: String
    let createdAt: Date
    var updatedAt: Date
    var resolutionNote: String
    var assignedModeratorId: UUID?
}

enum ModerationCaseActionType: String {
    case created
    case assigned
    case startedReview
    case resolvedApproved
    case resolvedRejected

    var title: String {
        switch self {
        case .created:
            return "Створено"
        case .assigned:
            return "Призначено"
        case .startedReview:
            return "Взято в роботу"
        case .resolvedApproved:
            return "Схвалено"
        case .resolvedRejected:
            return "Відхилено"
        }
    }
}

struct ModerationCaseAction: Identifiable {
    let id: UUID
    let caseId: UUID
    let actorUserId: UUID?
    let assignedModeratorId: UUID?
    let type: ModerationCaseActionType
    let note: String
    let createdAt: Date
}

enum AuditEventType: String, CaseIterable, Identifiable {
    case payout
    case escrow
    case moderation
    case risk
    case auth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .payout:
            return "Виплати"
        case .escrow:
            return "Ескроу"
        case .moderation:
            return "Модерація"
        case .risk:
            return "Ризик"
        case .auth:
            return "Безпека"
        }
    }
}

struct AuditEvent: Identifiable {
    let id: UUID
    let userId: UUID?
    let actorUserId: UUID?
    let type: AuditEventType
    let title: String
    let message: String
    let relatedId: UUID?
    let createdAt: Date
}
