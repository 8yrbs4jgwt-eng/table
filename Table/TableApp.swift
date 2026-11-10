import SwiftUI

@main
struct TableApp: App {
    @StateObject private var health = HealthManager()
    @StateObject private var timetable = TimetableStore()
    @StateObject private var events = EventStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(health)
                .environmentObject(timetable)
                .environmentObject(events)
                .environment(\.locale, .ru)
                .environment(\.calendar, .app)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await health.refresh()
                        await timetable.load(month: Date())
                    }
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Сегодня", systemImage: "sun.max.fill") }
            CalendarView()
                .tabItem { Label("Календарь", systemImage: "calendar") }
            HealthView()
                .tabItem { Label("Здоровье", systemImage: "heart.fill") }
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
        }
    }
}
