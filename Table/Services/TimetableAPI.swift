import Foundation

/// Клиент открытого API расписания СПбГУ: https://timetable.spbu.ru/api/docs
enum TimetableAPI {
    /// Подразделение «Менеджмент» (Высшая школа менеджмента).
    static let divisionAlias = "GSOM"

    private static let base = "https://timetable.spbu.ru/api/v1"

    /// Время в API приходит без часового пояса — это время Санкт-Петербурга.
    private static let dateTimeParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    enum APIError: LocalizedError {
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "Сервер расписания ответил с ошибкой (\(code))."
            }
        }
    }

    private static func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badResponse(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Уровни обучения → направления → годы поступления.
    static func levels() async throws -> [StudyLevel] {
        try await get("/study/divisions/\(divisionAlias)/programs/levels")
    }

    /// Группы направления выбранного года поступления.
    static func groups(programId: Int) async throws -> [StudentGroup] {
        let response: GroupsResponse = try await get("/programs/\(programId)/groups")
        return response.groups
    }

    /// Занятия группы за период [from, to).
    static func lessons(groupId: Int, from: Date, to: Date) async throws -> [Lesson] {
        let path = "/groups/\(groupId)/events/\(dayFormatter.string(from: from))/\(dayFormatter.string(from: to))"
        let response: EventsResponse = try await get(path)
        var result: [Lesson] = []
        for day in response.days ?? [] {
            for raw in day.events ?? [] {
                guard let startText = raw.start, let start = dateTimeParser.date(from: startText) else { continue }
                let end = raw.end.flatMap { dateTimeParser.date(from: $0) } ?? start
                result.append(Lesson(
                    start: start,
                    end: end,
                    subject: raw.subject ?? "Занятие",
                    location: raw.location ?? "",
                    educators: raw.educators ?? "",
                    isCancelled: raw.isCancelled ?? false
                ))
            }
        }
        return result.sorted { $0.start < $1.start }
    }
}
