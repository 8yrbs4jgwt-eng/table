import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var health: HealthManager
    @EnvironmentObject private var timetable: TimetableStore
    @AppStorage("stepGoal") private var stepGoal = 10_000

    @State private var editing: UserEvent?
    @State private var showGroupSetup = false

    private var steps: Double { health.values[.steps] ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    stepsCard
                    nextLessonCard
                    scheduleCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Сегодня")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = EventEditor.draft(for: Date())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить событие")
                }
            }
            .refreshable {
                await health.refresh()
                await timetable.load(month: Date(), force: true)
            }
            .task {
                await health.refresh()
                await timetable.load(month: Date())
            }
            .sheet(item: $editing) { event in
                EventEditor(event: event)
            }
            .sheet(isPresented: $showGroupSetup) {
                GroupSetupView()
            }
        }
    }

    // MARK: Шаги

    @ViewBuilder
    private var stepsCard: some View {
        Card {
            if !health.isAvailable {
                Label("Данные «Здоровья» недоступны на этом устройстве", systemImage: "heart.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !health.accessRequested {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Подключите «Здоровье»", systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("Шаги, дистанция, пульс, сон и другие показатели будут появляться здесь автоматически.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Подключить") {
                        Task { await health.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 20) {
                    ProgressRing(progress: steps / Double(max(stepGoal, 1)), color: .green)
                        .frame(width: 92, height: 92)
                        .overlay {
                            Image(systemName: "figure.walk")
                                .font(.title)
                                .foregroundStyle(.green)
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Шаги").font(.subheadline).foregroundStyle(.secondary)
                        Text(HealthMetric.steps.format(steps))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("цель — \(HealthMetric.steps.format(Double(stepGoal)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Расписание

    @ViewBuilder
    private var nextLessonCard: some View {
        if let next = timetable.nextLesson() {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(nextLessonCaption(next))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.accentColor)
                    LessonRow(lesson: next)
                }
            }
        }
    }

    private func nextLessonCaption(_ lesson: Lesson) -> String {
        let now = Date()
        if lesson.start <= now { return "Идёт сейчас" }
        let calendar = Calendar.app
        if calendar.isDateInToday(lesson.start) {
            let minutes = max(Int(lesson.start.timeIntervalSince(now) / 60), 1)
            if minutes < 60 { return "Следующая пара через \(minutes) мин" }
            return "Следующая пара через \(minutes / 60) ч \(minutes % 60) мин"
        }
        if calendar.isDateInTomorrow(lesson.start) { return "Следующая пара завтра" }
        return "Следующая пара — " + lesson.start.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.ru))
    }

    private var scheduleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.ru)).capitalizedFirst)
                        .font(.headline)
                    Spacer()
                    if timetable.isLoading { ProgressView() }
                }
                if timetable.selection == nil {
                    Button {
                        showGroupSetup = true
                    } label: {
                        Label("Выбрать группу, чтобы видеть расписание", systemImage: "graduationcap.fill")
                            .font(.subheadline)
                    }
                }
                AgendaList(day: Date()) { editing = $0 }
                if let message = timetable.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
        }
        .padding(5)
    }
}

extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
