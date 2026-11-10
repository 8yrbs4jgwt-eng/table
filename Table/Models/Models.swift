import Foundation

// MARK: - Общий календарь приложения (неделя с понедельника, русская локаль)

extension Calendar {
    static let app: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        return calendar
    }()
}

extension Locale {
    static let ru = Locale(identifier: "ru_RU")
}

// MARK: - Справочники расписания СПбГУ

struct StudyLevel: Decodable, Hashable {
    let name: String
    let programs: [StudyProgram]

    enum CodingKeys: String, CodingKey {
        case name = "StudyLevelName"
        case programs = "StudyProgramCombinations"
    }
}

struct StudyProgram: Decodable, Hashable {
    let name: String
    let years: [AdmissionYear]

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case years = "AdmissionYears"
    }
}

struct AdmissionYear: Decodable, Hashable {
    let programId: Int
    let yearName: String
    let isEmpty: Bool?

    enum CodingKeys: String, CodingKey {
        case programId = "StudyProgramId"
        case yearName = "YearName"
        case isEmpty = "IsEmpty"
    }
}

struct GroupsResponse: Decodable {
    let groups: [StudentGroup]

    enum CodingKeys: String, CodingKey {
        case groups = "Groups"
    }
}

struct StudentGroup: Decodable, Hashable {
    let id: Int
    let name: String
    let studyForm: String?
    let profiles: String?

    enum CodingKeys: String, CodingKey {
        case id = "StudentGroupId"
        case name = "StudentGroupName"
        case studyForm = "StudentGroupStudyForm"
        case profiles = "StudentGroupProfiles"
    }
}

/// Выбранная пользователем группа.
struct GroupSelection: Codable, Equatable {
    var levelName: String
    var programName: String
    var yearName: String
    var groupId: Int
    var groupName: String
}

// MARK: - Занятия

struct EventsResponse: Decodable {
    let days: [Day]?

    enum CodingKeys: String, CodingKey {
        case days = "Days"
    }

    struct Day: Decodable {
        let events: [RawEvent]?

        enum CodingKeys: String, CodingKey {
            case events = "DayStudyEvents"
        }
    }

    struct RawEvent: Decodable {
        let start: String?
        let end: String?
        let subject: String?
        let location: String?
        let educators: String?
        let isCancelled: Bool?

        enum CodingKeys: String, CodingKey {
            case start = "Start"
            case end = "End"
            case subject = "Subject"
            case location = "LocationsDisplayText"
            case educators = "EducatorsDisplayText"
            case isCancelled = "IsCancelled"
        }
    }
}

struct Lesson: Codable, Hashable, Identifiable {
    var start: Date
    var end: Date
    var subject: String
    var location: String
    var educators: String
    var isCancelled: Bool

    var id: String { "\(start.timeIntervalSince1970)|\(subject)|\(location)|\(educators)" }

    /// «Название, вид занятия» → («Название», «вид занятия»)
    var titleAndKind: (title: String, kind: String?) {
        guard let range = subject.range(of: ", ", options: .backwards) else { return (subject, nil) }
        let kind = String(subject[range.upperBound...])
        // Вид занятия — короткий хвост в нижнем регистре («лекция», «практическое занятие» …)
        guard kind.count <= 40, let first = kind.first, first.isLowercase else { return (subject, nil) }
        return (String(subject[..<range.lowerBound]), kind)
    }
}

// MARK: - Свои события

struct UserEvent: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String = ""
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var location: String = ""
    var notes: String = ""
}

/// Строка расписания дня: занятие или своё событие.
enum AgendaItem: Identifiable, Hashable {
    case lesson(Lesson)
    case event(UserEvent)

    var id: String {
        switch self {
        case .lesson(let lesson): return "l-" + lesson.id
        case .event(let event): return "e-" + event.id.uuidString
        }
    }

    var start: Date {
        switch self {
        case .lesson(let lesson): return lesson.start
        case .event(let event): return event.start
        }
    }

    var end: Date {
        switch self {
        case .lesson(let lesson): return lesson.end
        case .event(let event): return event.end
        }
    }

    var isAllDay: Bool {
        if case .event(let event) = self { return event.isAllDay }
        return false
    }
}
