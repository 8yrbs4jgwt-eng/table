import Foundation

/// Свои события пользователя, хранятся в JSON-файле на устройстве.
@MainActor
final class EventStore: ObservableObject {
    @Published private(set) var events: [UserEvent] = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("events.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([UserEvent].self, from: data) {
            events = saved
        }
    }

    func events(on day: Date) -> [UserEvent] {
        let calendar = Calendar.app
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return events
            .filter { event in
                // Событие попадает в день, если пересекается с ним (в т.ч. многодневное).
                let end = max(event.end, event.start)
                return event.start < dayEnd && (end > dayStart || calendar.isDate(event.start, inSameDayAs: dayStart))
            }
            .sorted { $0.start < $1.start }
    }

    func save(_ event: UserEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
        persist()
    }

    func delete(_ event: UserEvent) {
        events.removeAll { $0.id == event.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
