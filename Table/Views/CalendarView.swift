import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var timetable: TimetableStore
    @EnvironmentObject private var events: EventStore

    @State private var month = Calendar.app.startOfDay(for: Date())
    @State private var selected = Calendar.app.startOfDay(for: Date())
    @State private var editing: UserEvent?

    private let calendar = Calendar.app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card {
                        VStack(spacing: 12) {
                            monthHeader
                            weekdayHeader
                            monthGrid
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.ru)).capitalizedFirst)
                                    .font(.headline)
                                Spacer()
                                if timetable.isLoading { ProgressView() }
                            }
                            AgendaList(day: selected) { editing = $0 }
                            if let message = timetable.errorMessage {
                                Text(message).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Календарь")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сегодня") {
                        let today = calendar.startOfDay(for: Date())
                        withAnimation { month = today; selected = today }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = EventEditor.draft(for: selected)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить событие")
                }
            }
            .refreshable { await timetable.load(month: month, force: true) }
            .task(id: monthKey) { await timetable.load(month: month) }
            .sheet(item: $editing) { event in
                EventEditor(event: event)
            }
        }
    }

    private var monthKey: String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(timetable.selection?.groupId ?? 0)"
    }

    // MARK: Шапка месяца

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 36)
            }
            .accessibilityLabel("Предыдущий месяц")
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year().locale(.ru)).capitalizedFirst)
                .font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 36)
            }
            .accessibilityLabel("Следующий месяц")
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { name in
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Сетка

    /// Дни месяца с пустыми ячейками в начале (неделя с понедельника).
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayCount = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start) // 1 = вс
        let leading = (weekday + 5) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            result.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        return result
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(
                        day: day,
                        isSelected: calendar.isDate(day, inSameDayAs: selected),
                        isToday: calendar.isDateInToday(day),
                        hasLessons: !timetable.lessons(on: day).isEmpty,
                        hasEvents: !events.events(on: day).isEmpty
                    )
                    .onTapGesture { selected = day }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                shiftMonth(value.translation.width < 0 ? 1 : -1)
            }
        )
    }

    private func shiftMonth(_ delta: Int) {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start,
              let next = calendar.date(byAdding: .month, value: delta, to: start) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            month = next
            // В текущем месяце выделяем сегодняшний день, в остальных — первое число.
            let today = calendar.startOfDay(for: Date())
            selected = calendar.isDate(today, equalTo: next, toGranularity: .month) ? today : next
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let hasLessons: Bool
    let hasEvents: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.app.component(.day, from: day))")
                .font(.body.weight(isToday || isSelected ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                .frame(width: 34, height: 34)
                .background {
                    if isSelected {
                        Circle().fill(Color.accentColor)
                    } else if isToday {
                        Circle().fill(Color.accentColor.opacity(0.15))
                    }
                }
            HStack(spacing: 3) {
                Circle().fill(Color.accentColor).frame(width: 5, height: 5).opacity(hasLessons ? 1 : 0)
                Circle().fill(Color.orange).frame(width: 5, height: 5).opacity(hasEvents ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.day().month(.wide).locale(.ru)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
