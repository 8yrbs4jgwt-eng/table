import Foundation

/// Хранит выбранную группу и кэш занятий по месяцам.
@MainActor
final class TimetableStore: ObservableObject {
    @Published var selection: GroupSelection? {
        didSet {
            guard selection != oldValue else { return }
            saveSelection()
            months = [:]
            fetchedAt = [:]
            rebuildIndex()
            saveCache()
        }
    }
    @Published private(set) var byDay: [Date: [Lesson]] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var months: [String: [Lesson]] = [:]
    private var fetchedAt: [String: Date] = [:]
    private var inFlight: Set<String> = []

    private let selectionKey = "timetable.selection"
    private let staleAfter: TimeInterval = 3 * 60 * 60

    private struct Cache: Codable {
        var groupId: Int
        var months: [String: [Lesson]]
        var fetchedAt: [String: Date]
    }

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("timetable-cache.json")
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: selectionKey),
           let saved = try? JSONDecoder().decode(GroupSelection.self, from: data) {
            selection = saved
        }
        if let selection,
           let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(Cache.self, from: data),
           cache.groupId == selection.groupId {
            months = cache.months
            fetchedAt = cache.fetchedAt
            rebuildIndex()
        }
    }

    // MARK: Чтение

    func lessons(on day: Date) -> [Lesson] {
        byDay[Calendar.app.startOfDay(for: day)] ?? []
    }

    /// Ближайшее ещё не закончившееся занятие.
    func nextLesson(after date: Date = Date()) -> Lesson? {
        byDay.values.joined()
            .filter { $0.end > date && !$0.isCancelled }
            .min { $0.start < $1.start }
    }

    // MARK: Загрузка

    /// Загружает занятия месяца, в который попадает `date`.
    func load(month date: Date, force: Bool = false) async {
        guard let selection else { return }
        let calendar = Calendar.app
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return }
        let key = Self.monthKey(interval.start)

        if !force, let fetched = fetchedAt[key], Date().timeIntervalSince(fetched) < staleAfter { return }
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        isLoading = true
        defer {
            inFlight.remove(key)
            isLoading = !inFlight.isEmpty
        }

        do {
            // Берём день с запасом по краям, затем отбрасываем лишнее.
            let from = calendar.date(byAdding: .day, value: -1, to: interval.start) ?? interval.start
            let to = calendar.date(byAdding: .day, value: 1, to: interval.end) ?? interval.end
            let loaded = try await TimetableAPI.lessons(groupId: selection.groupId, from: from, to: to)
            guard self.selection?.groupId == selection.groupId else { return }
            months[key] = loaded.filter { interval.contains($0.start) }
            fetchedAt[key] = Date()
            errorMessage = nil
            rebuildIndex()
            saveCache()
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = "Не удалось обновить расписание: \(error.localizedDescription)"
        }
    }

    // MARK: Внутреннее

    private static func monthKey(_ date: Date) -> String {
        let parts = Calendar.app.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    private func rebuildIndex() {
        var index: [Date: [Lesson]] = [:]
        var seen = Set<String>()
        for lesson in months.values.joined() where seen.insert(lesson.id).inserted {
            index[Calendar.app.startOfDay(for: lesson.start), default: []].append(lesson)
        }
        for key in index.keys {
            index[key]?.sort { $0.start < $1.start }
        }
        byDay = index
    }

    private func saveSelection() {
        if let selection, let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: selectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectionKey)
        }
    }

    private func saveCache() {
        guard let selection else {
            try? FileManager.default.removeItem(at: cacheURL)
            return
        }
        let cache = Cache(groupId: selection.groupId, months: months, fetchedAt: fetchedAt)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
