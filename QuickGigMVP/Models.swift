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
