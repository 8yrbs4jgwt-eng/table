import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var health: HealthManager
    @EnvironmentObject private var timetable: TimetableStore
    @AppStorage("stepGoal") private var stepGoal = 10_000
    @State private var showGroupSetup = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let selection = timetable.selection {
                        LabeledContent("Группа", value: selection.groupName)
                        LabeledContent("Направление", value: selection.programName)
                        LabeledContent("Уровень", value: selection.levelName)
                        LabeledContent("Год поступления", value: selection.yearName)
                        Button("Сменить группу") { showGroupSetup = true }
                        Button("Отключить расписание", role: .destructive) { timetable.selection = nil }
                    } else {
                        Button {
                            showGroupSetup = true
                        } label: {
                            Label("Выбрать направление и группу", systemImage: "graduationcap.fill")
                        }
                    }
                } header: {
                    Text("Расписание СПбГУ · Менеджмент")
                } footer: {
                    Text("Занятия подгружаются с timetable.spbu.ru и появляются в календаре автоматически.")
                }

                Section {
                    if !health.isAvailable {
                        Text("Данные «Здоровья» недоступны на этом устройстве.")
                            .foregroundStyle(.secondary)
                    } else {
                        Stepper(value: $stepGoal, in: 1_000...50_000, step: 500) {
                            LabeledContent("Цель по шагам", value: HealthMetric.steps.format(Double(stepGoal)))
                        }
                        Button(health.accessRequested ? "Запросить доступ ещё раз" : "Подключить «Здоровье»") {
                            Task { await health.requestAccess() }
                        }
                    }
                } header: {
                    Text("Здоровье")
                } footer: {
                    Text("Приложение только читает данные. Уже выданные разрешения меняются в Настройки → Здоровье → Доступ к данным и устройствам.")
                }

                if health.isAvailable {
                    Section("Показатели на экране «Здоровье»") {
                        MetricToggles()
                    }
                }
            }
            .navigationTitle("Настройки")
            .sheet(isPresented: $showGroupSetup) {
                GroupSetupView()
            }
        }
    }
}

// MARK: - Выбор группы: уровень → направление → год → группа

struct GroupSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var levels: [StudyLevel] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let errorMessage {
                    LoadError(message: errorMessage) { Task { await load() } }
                } else {
                    Section("Уровень обучения") {
                        ForEach(levels, id: \.self) { level in
                            NavigationLink(level.name) {
                                ProgramList(level: level, close: { dismiss() })
                            }
                        }
                    }
                }
            }
            .navigationTitle("Менеджмент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            levels = try await TimetableAPI.levels()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct ProgramList: View {
    let level: StudyLevel
    let close: () -> Void

    var body: some View {
        List {
            Section("Направление") {
                ForEach(level.programs, id: \.self) { program in
                    NavigationLink(program.name) {
                        YearList(level: level, program: program, close: close)
                    }
                }
            }
        }
        .navigationTitle(level.name)
    }
}

private struct YearList: View {
    let level: StudyLevel
    let program: StudyProgram
    let close: () -> Void

    var body: some View {
        List {
            Section("Год поступления") {
                ForEach(program.years.filter { $0.isEmpty != true }, id: \.self) { year in
                    NavigationLink(year.yearName) {
                        GroupList(level: level, program: program, year: year, close: close)
                    }
                }
            }
        }
        .navigationTitle(program.name)
    }
}

private struct GroupList: View {
    @EnvironmentObject private var timetable: TimetableStore

    let level: StudyLevel
    let program: StudyProgram
    let year: AdmissionYear
    let close: () -> Void

    @State private var groups: [StudentGroup] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let errorMessage {
                LoadError(message: errorMessage) { Task { await load() } }
            } else if groups.isEmpty {
                Text("Групп не найдено").foregroundStyle(.secondary)
            } else {
                Section("Группа") {
                    ForEach(groups, id: \.self) { group in
                        Button {
                            timetable.selection = GroupSelection(
                                levelName: level.name,
                                programName: program.name,
                                yearName: year.yearName,
                                groupId: group.id,
                                groupName: group.name
                            )
                            close()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name).foregroundStyle(.primary)
                                    let details = [group.studyForm, group.profiles]
                                        .compactMap { $0 }
                                        .filter { !$0.isEmpty }
                                        .joined(separator: " · ")
                                    if !details.isEmpty {
                                        Text(details).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if timetable.selection?.groupId == group.id {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(year.yearName)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            groups = try await TimetableAPI.groups(programId: year.programId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct LoadError: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Не удалось загрузить данные").font(.headline)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button("Повторить", action: retry)
        }
        .padding(.vertical, 4)
    }
}
