import Foundation
import CoreLocation

enum UserRole: String, CaseIterable, Identifiable {
    case worker
    case employer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .worker:
            return "Работник"
        case .employer:
            return "Работодатель"
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
            return "Ожидает"
        case .accepted:
            return "Принят"
        case .rejected:
            return "Отклонен"
        }
    }
}

struct AppUser: Identifiable {
    let id: UUID
    var name: String
    var email: String
    var password: String
    var role: UserRole
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
    var pay: Int
    var startDate: Date
    var endDate: Date
    var coordinate: CLLocationCoordinate2D
    var employerId: UUID

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
    let createdAt: Date
}

struct Review: Identifiable {
    let id: UUID
    let fromUserId: UUID
    let toUserId: UUID
    let stars: Int
    let comment: String
    let date: Date
}
