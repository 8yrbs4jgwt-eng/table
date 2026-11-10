import Charts
import SwiftUI

struct HealthView: View {
    @EnvironmentObject private var health: HealthManager
    @AppStorage("stepGoal") private var stepGoal = 10_000
    @State private var showMetricPicker = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !health.isAvailable {
                        ContentUnavailableView(
                            "«Здоровье» недоступно",
                            systemImage: "heart.slash",
                            description: Text("На этом устройстве нет данных приложения «Здоровье».")
                        )
                    } else if !health.accessRequested {
                        connectCard
                    } else {
                        weekChart
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(health.enabledMetrics) { metric in
                                MetricTile(metric: metric, value: health.values[metric])
                            }
                        }
                        Text("Если показатель пуст — в «Здоровье» нет записей за этот период или доступ к нему выключен: Настройки → Здоровье → Доступ к данным → Table.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let message = health.errorMessage {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Здоровье")
            .toolbar {
                if health.isAvailable && health.accessRequested {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showMetricPicker = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("Выбрать показатели")
                    }
                }
            }
            .refreshable { await health.refresh() }
            .task { await health.refresh() }
            .sheet(isPresented: $showMetricPicker) {
                NavigationStack {
                    List { MetricToggles() }
                        .navigationTitle("Показатели")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Готово") { showMetricPicker = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var connectCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Подключите «Здоровье»", systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("Приложение только читает данные: шаги, дистанцию, калории, этажи, упражнения, пульс, вариабельность пульса, кислород в крови, сон, вес и воду. Ничего не записывается и никуда не отправляется.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Подключить") {
                    Task { await health.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var weekChart: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Шаги за неделю").font(.headline)
                if health.weekSteps.isEmpty {
                    Text("Пока нет данных")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    Chart {
                        ForEach(health.weekSteps) { day in
                            BarMark(
                                x: .value("День", day.date, unit: .day),
                                y: .value("Шаги", day.steps)
                            )
                            .foregroundStyle(day.steps >= Double(stepGoal) ? Color.green : Color.green.opacity(0.45))
                            .cornerRadius(5)
                        }
                        RuleMark(y: .value("Цель", Double(stepGoal)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated).locale(.ru), centered: true)
                        }
                    }
                    .frame(height: 170)
                }
            }
        }
    }
}

private struct MetricTile: View {
    let metric: HealthMetric
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(metric.title, systemImage: metric.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(metric.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map(metric.format) ?? "—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if value != nil {
                    Text(metric.unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(value == nil ? "нет данных" : metric.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Переключатели показателей — используются и на экране «Здоровье», и в настройках.
struct MetricToggles: View {
    @EnvironmentObject private var health: HealthManager

    var body: some View {
        ForEach(HealthMetric.allCases) { metric in
            Toggle(isOn: Binding(
                get: { health.isEnabled(metric) },
                set: { health.setEnabled(metric, $0) }
            )) {
                Label {
                    Text(metric.title)
                } icon: {
                    Image(systemName: metric.icon).foregroundStyle(metric.color)
                }
            }
        }
    }
}
