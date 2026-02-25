import Foundation

struct APIAuthUser: Decodable {
    let id: Int
    let name: String
    let phone: String
    let email: String?
    let role: String
    let rating: Double?
    let reviewsCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case phone
        case email
        case role
        case rating
        case reviewsCount = "reviews_count"
    }
}

struct APIAuthResponse: Decodable {
    let token: String
    let user: APIAuthUser
}

struct APIMeResponse: Decodable {
    let user: APIAuthUser
}

enum APIClientError: LocalizedError {
    case invalidURL
    case transport(String)
    case server(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некоректна адреса API"
        case .transport(let message):
            return message
        case .server(let message):
            return message
        case .decoding:
            return "Не вдалося обробити відповідь сервера"
        }
    }
}

final class AuthAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func register(name: String, phone: String, password: String, role: UserRole) async throws -> APIAuthResponse {
        let body: [String: Any] = [
            "name": name,
            "phone": phone,
            "password": password,
            "role": role.rawValue
        ]
        return try await request(path: "/register", method: "POST", body: body, authorizedBy: nil, responseType: APIAuthResponse.self)
    }

    func login(phone: String, password: String) async throws -> APIAuthResponse {
        let body: [String: Any] = [
            "phone": phone,
            "password": password
        ]
        return try await request(path: "/login", method: "POST", body: body, authorizedBy: nil, responseType: APIAuthResponse.self)
    }

    func me(token: String) async throws -> APIMeResponse {
        try await request(path: "/me", method: "GET", body: nil, authorizedBy: token, responseType: APIMeResponse.self)
    }

    func logout(token: String) async throws {
        _ = try await request(path: "/logout", method: "POST", body: nil, authorizedBy: token, responseType: EmptyResponse.self)
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        body: [String: Any]?,
        authorizedBy token: String?,
        responseType: T.Type
    ) async throws -> T {
        guard let url = endpoint(path: path) else {
            throw APIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIClientError.transport("Немає з'єднання з сервером. Перевірте APIBaseURL і запуск backend")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.transport("Сервер повернув некоректну відповідь")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseServerMessage(from: data) ?? "Помилка сервера (\(httpResponse.statusCode))"
            throw APIClientError.server(message)
        }

        if T.self == EmptyResponse.self {
            // swiftlint:disable:next force_cast
            return EmptyResponse() as! T
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIClientError.decoding
        }
    }

    private func endpoint(path: String) -> URL? {
        let infoURL = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        let base = (infoURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? infoURL!
            : "http://127.0.0.1:8000/api"
        return URL(string: base + path)
    }

    private func parseServerMessage(from data: Data) -> String? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if let errors = raw["errors"] as? [String: [String]],
           let firstField = errors.values.first,
           let firstMessage = firstField.first,
           !firstMessage.isEmpty {
            return firstMessage
        }

        if let message = raw["message"] as? String, !message.isEmpty {
            return message
        }

        return nil
    }
}

private struct EmptyResponse: Decodable {}
