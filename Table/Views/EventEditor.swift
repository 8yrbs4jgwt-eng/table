import SwiftUI

/// Создание и редактирование своего события.
struct EventEditor: View {
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss

    @State private var event: UserEvent
    private let isNew: Bool

    init(event: UserEvent) {
        _event = State(initialValue: event)
        isNew = event.title.isEmpty && event.notes.isEmpty && event.location.isEmpty
    }

    /// Заготовка события на ближайший целый час выбранного дня.
    static func draft(for day: Date) -> UserEvent {
        let calendar = Calendar.app
        let hour = min(calendar.component(.hour, from: Date()) + 1, 23)
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return UserEvent(start: start, end: start.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $event.title)
                    TextField("Место", text: $event.location)
                }
                Section {
                    Toggle("Весь день", isOn: $event.isAllDay)
                    DatePicker("Начало", selection: $event.start, displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Конец", selection: $event.end, in: event.start..., displayedComponents: event.isAllDay ? [.date] : [.date, .hourAndMinute])
                }
                Section("Заметки") {
                    TextField("Заметки", text: $event.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if !isNew {
                    Section {
                        Button("Удалить событие", role: .destructive) {
                            events.delete(event)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Новое событие" : "Событие")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        events.save(event)
                        dismiss()
                    }
                    .disabled(event.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: event.start) { old, new in
                // Сдвигаем конец вместе с началом, сохраняя длительность.
                let duration = max(event.end.timeIntervalSince(old), 0)
                event.end = new.addingTimeInterval(duration)
            }
        }
    }
}
