import SwiftUI

extension Date {
    var timeText: String {
        formatted(.dateTime.hour().minute().locale(.ru))
    }
}

/// Карточка-контейнер в едином стиле.
struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Строка занятия: когда, что, где, кто.
struct LessonRow: View {
    let lesson: Lesson

    var body: some View {
        let parts = lesson.titleAndKind
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(lesson.start.timeText).font(.subheadline.weight(.semibold))
                Text(lesson.end.timeText).font(.caption).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(width: 48, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(lesson.isCancelled ? Color.gray : Color.accentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(parts.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(lesson.isCancelled)
                if lesson.isCancelled {
                    Text("Отменено").font(.caption.weight(.semibold)).foregroundStyle(.red)
                } else if let kind = parts.kind {
                    Text(kind).font(.caption).foregroundStyle(.secondary)
                }
                if !lesson.location.isEmpty {
                    Label(lesson.location, systemImage: "mappin.and.ellipse")
                }
                if !lesson.educators.isEmpty {
                    Label(lesson.educators, systemImage: "person.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(lesson.isCancelled ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// Строка своего события.
struct UserEventRow: View {
    let event: UserEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                if event.isAllDay {
                    Text("весь").font(.subheadline.weight(.semibold))
                    Text("день").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(event.start.timeText).font(.subheadline.weight(.semibold))
                    Text(event.end.timeText).font(.caption).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .frame(width: 48, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title.isEmpty ? "Без названия" : event.title)
                    .font(.subheadline.weight(.semibold))
                if !event.location.isEmpty {
                    Label(event.location, systemImage: "mappin.and.ellipse").font(.caption)
                }
                if !event.notes.isEmpty {
                    Text(event.notes).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Список дел на день: занятия из расписания и свои события вперемешку по времени.
struct AgendaList: View {
    @EnvironmentObject private var timetable: TimetableStore
    @EnvironmentObject private var events: EventStore

    let day: Date
    var onEdit: (UserEvent) -> Void

    private var items: [AgendaItem] {
        let lessons = timetable.lessons(on: day).map(AgendaItem.lesson)
        let own = events.events(on: day).map(AgendaItem.event)
        return (lessons + own).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.start < rhs.start
        }
    }

    var body: some View {
        let items = self.items
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty {
                Text("Ничего не запланировано")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    switch item {
                    case .lesson(let lesson):
                        LessonRow(lesson: lesson)
                    case .event(let event):
                        Button { onEdit(event) } label: { UserEventRow(event: event) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
