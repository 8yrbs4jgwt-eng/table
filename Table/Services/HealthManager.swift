import Foundation
import HealthKit
import SwiftUI

/// Показатели из приложения «Здоровье», которые умеет показывать приложение.
enum HealthMetric: String, CaseIterable, Identifiable, Codable {
    case steps, distance, activeEnergy, flights, exercise
    case heartRate, restingHeartRate, hrv, oxygen
    case sleep, weight, water

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "Шаги"
        case .distance: return "Дистанция"
        case .activeEnergy: return "Активные калории"
        case .flights: return "Этажи"
        case .exercise: return "Упражнения"
        case .heartRate: return "Пульс"
        case .restingHeartRate: return "Пульс в покое"
        case .hrv: return "Вариабельность пульса"
        case .oxygen: return "Кислород в крови"
        case .sleep: return "Сон"
        case .weight: return "Вес"
        case .water: return "Вода"
        }
    }

    var subtitle: String {
        switch self {
        case .steps, .distance, .activeEnergy, .flights, .exercise, .water: return "сегодня"
        case .heartRate: return "среднее за сегодня"
        case .restingHeartRate, .hrv, .oxygen, .weight: return "последнее измерение"
        case .sleep: return "прошлая ночь"
        }
    }

    var unit: String {
        switch self {
        case .steps: return "шагов"
        case .distance: return "км"
        case .activeEnergy: return "ккал"
        case .flights: return "эт."
        case .exercise: return "мин"
        case .heartRate, .restingHeartRate: return "уд/мин"
        case .hrv: return "мс"
        case .oxygen: return "%"
        case .sleep: return "ч"
        case .weight: return "кг"
        case .water: return "л"
        }
    }

    var icon: String {
        switch self {
        case .steps: return "figure.walk"
        case .distance: return "map.fill"
        case .activeEnergy: return "flame.fill"
        case .flights: return "figure.stairs"
        case .exercise: return "figure.run"
        case .heartRate: return "heart.fill"
        case .restingHeartRate: return "heart.circle.fill"
        case .hrv: return "waveform.path.ecg"
        case .oxygen: return "lungs.fill"
        case .sleep: return "bed.double.fill"
        case .weight: return "scalemass.fill"
        case .water: return "drop.fill"
        }
    }

    var color: Color {
        switch self {
        case .steps: return .green
        case .distance: return .teal
        case .activeEnergy: return .orange
        case .flights: return .mint
        case .exercise: return .yellow
        case .heartRate, .restingHeartRate: return .red
        case .hrv: return .pink
        case .oxygen: return .cyan
        case .sleep: return .indigo
        case .weight: return .purple
        case .water: return .blue
        }
    }

    /// Показатели, включённые по умолчанию.
    static let defaults: [HealthMetric] = [.steps, .distance, .activeEnergy, .exercise, .heartRate, .sleep]

    func format(_ value: Double) -> String {
        switch self {
        case .steps, .activeEnergy, .flights, .exercise, .heartRate, .restingHeartRate, .hrv, .oxygen:
            return value.formatted(.number.precision(.fractionLength(0)).locale(.ru))
        case .distance:
            return value.formatted(.number.precision(.fractionLength(2)).locale(.ru))
        case .weight, .water:
            return value.formatted(.number.precision(.fractionLength(1)).locale(.ru))
        case .sleep:
            let minutes = Int((value * 60).rounded())
            return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
        }
    }

    fileprivate enum Source {
        case sumToday(HKQuantityTypeIdentifier, HKUnit)
        case averageToday(HKQuantityTypeIdentifier, HKUnit)
        case latest(HKQuantityTypeIdentifier, HKUnit, scale: Double)
        case sleep
    }

    fileprivate var source: Source {
        switch self {
        case .steps: return .sumToday(.stepCount, .count())
        case .distance: return .sumToday(.distanceWalkingRunning, .meterUnit(with: .kilo))
        case .activeEnergy: return .sumToday(.activeEnergyBurned, .kilocalorie())
        case .flights: return .sumToday(.flightsClimbed, .count())
        case .exercise: return .sumToday(.appleExerciseTime, .minute())
        case .water: return .sumToday(.dietaryWater, .liter())
        case .heartRate: return .averageToday(.heartRate, HKUnit.count().unitDivided(by: .minute()))
        case .restingHeartRate: return .latest(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), scale: 1)
        case .hrv: return .latest(.heartRateVariabilitySDNN, .secondUnit(with: .milli), scale: 1)
        case .oxygen: return .latest(.oxygenSaturation, .percent(), scale: 100)
        case .weight: return .latest(.bodyMass, .gramUnit(with: .kilo), scale: 1)
        case .sleep: return .sleep
        }
    }

    fileprivate var objectType: HKObjectType {
        switch source {
        case .sumToday(let id, _), .averageToday(let id, _), .latest(let id, _, _):
            return HKQuantityType(id)
        case .sleep:
            return HKCategoryType(.sleepAnalysis)
        }
    }
}

struct DaySteps: Identifiable, Hashable {
    let date: Date
    let steps: Double
    var id: Date { date }
}

@MainActor
final class HealthManager: ObservableObject {
    @Published private(set) var values: [HealthMetric: Double] = [:]
    @Published private(set) var weekSteps: [DaySteps] = []
    @Published private(set) var accessRequested: Bool
    @Published var enabledMetrics: [HealthMetric] {
        didSet {
            UserDefaults.standard.set(enabledMetrics.map(\.rawValue), forKey: Self.enabledKey)
        }
    }
    @Published var errorMessage: String?

    let isAvailable = HKHealthStore.isHealthDataAvailable()

    private let store = HKHealthStore()
    private static let requestedKey = "health.accessRequested"
    private static let enabledKey = "health.enabledMetrics"

    init() {
        accessRequested = UserDefaults.standard.bool(forKey: Self.requestedKey)
        if let saved = UserDefaults.standard.stringArray(forKey: Self.enabledKey) {
            enabledMetrics = saved.compactMap(HealthMetric.init(rawValue:))
        } else {
            enabledMetrics = HealthMetric.defaults
        }
    }

    func isEnabled(_ metric: HealthMetric) -> Bool {
        enabledMetrics.contains(metric)
    }

    func setEnabled(_ metric: HealthMetric, _ enabled: Bool) {
        var set = Set(enabledMetrics)
        if enabled { set.insert(metric) } else { set.remove(metric) }
        // Сохраняем единый порядок показателей.
        enabledMetrics = HealthMetric.allCases.filter(set.contains)
        if enabled { Task { await refresh() } }
    }

    /// Запрашивает доступ на чтение сразу ко всем поддерживаемым показателям.
    func requestAccess() async {
        guard isAvailable else {
            errorMessage = "Данные «Здоровья» недоступны на этом устройстве."
            return
        }
        do {
            let types = Set(HealthMetric.allCases.map(\.objectType))
            try await store.requestAuthorization(toShare: [], read: types)
            accessRequested = true
            UserDefaults.standard.set(true, forKey: Self.requestedKey)
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = "Не удалось получить доступ к «Здоровью»: \(error.localizedDescription)"
        }
    }

    func refresh() async {
        guard isAvailable, accessRequested else { return }
        var fresh: [HealthMetric: Double] = [:]
        // Шаги нужны всегда — для экрана «Сегодня».
        let metrics = Set(enabledMetrics).union([.steps])
        for metric in metrics {
            if let value = await value(for: metric) {
                fresh[metric] = value
            }
        }
        values = fresh
        weekSteps = await dailySteps(days: 7)
    }

    // MARK: Запросы HealthKit

    private func value(for metric: HealthMetric) async -> Double? {
        switch metric.source {
        case .sumToday(let id, let unit):
            return await statisticsToday(id, unit: unit, options: .cumulativeSum)
        case .averageToday(let id, let unit):
            return await statisticsToday(id, unit: unit, options: .discreteAverage)
        case .latest(let id, let unit, let scale):
            return await latest(id, unit: unit).map { $0 * scale }
        case .sleep:
            return await sleepHours()
        }
    }

    private func statisticsToday(_ id: HKQuantityTypeIdentifier, unit: HKUnit, options: HKStatisticsOptions) async -> Double? {
        let start = Calendar.app.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let store = self.store
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate, options: options) { _, statistics, _ in
                let quantity = options.contains(.cumulativeSum) ? statistics?.sumQuantity() : statistics?.averageQuantity()
                continuation.resume(returning: quantity?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let store = self.store
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType(id), predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let sample = samples?.first as? HKQuantitySample
                continuation.resume(returning: sample?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Сон за прошлую ночь (с 18:00 вчера), в часах. Пересекающиеся записи разных источников объединяются.
    private func sleepHours() async -> Double? {
        let calendar = Calendar.app
        let todayStart = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .hour, value: -6, to: todayStart) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: Date(), options: [])
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let store = self.store
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let intervals = (samples ?? [])
                    .compactMap { $0 as? HKCategorySample }
                    .filter { asleep.contains($0.value) }
                    .map { (start: max($0.startDate, from), end: $0.endDate) }
                    .sorted { $0.start < $1.start }
                var total: TimeInterval = 0
                var current: (start: Date, end: Date)?
                for interval in intervals {
                    if let open = current, interval.start <= open.end {
                        current = (open.start, max(open.end, interval.end))
                    } else {
                        if let open = current { total += open.end.timeIntervalSince(open.start) }
                        current = interval
                    }
                }
                if let open = current { total += open.end.timeIntervalSince(open.start) }
                continuation.resume(returning: total > 0 ? total / 3600 : nil)
            }
            store.execute(query)
        }
    }

    private func dailySteps(days: Int) async -> [DaySteps] {
        let calendar = Calendar.app
        let todayStart = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: from, end: Date(), options: .strictStartDate)
        let store = self.store
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: from,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var result: [DaySteps] = []
                collection?.enumerateStatistics(from: from, to: Date()) { statistics, _ in
                    let steps = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    result.append(DaySteps(date: statistics.startDate, steps: steps))
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }
}
