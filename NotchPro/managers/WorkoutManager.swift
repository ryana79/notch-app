//
//  WorkoutManager.swift
//  NotchPro
//

import Combine
import Defaults
import Foundation

struct WorkoutSet: Identifiable, Codable, Equatable {
    let id: UUID
    var exerciseName: String
    var weight: Double
    var reps: Int
    var completedAt: Date

    init(id: UUID = UUID(), exerciseName: String, weight: Double, reps: Int, completedAt: Date = .now) {
        self.id = id
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.completedAt = completedAt
    }

    var volume: Double { weight * Double(reps) }

    var displaySummary: String {
        "\(formatWorkoutWeight(weight)) lb × \(reps)"
    }

    var loggedDayLabel: String {
        formatWorkoutDayLabel(completedAt)
    }
}

struct WorkoutSession: Identifiable, Codable, Equatable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var sets: [WorkoutSet]

    init(id: UUID = UUID(), startedAt: Date = .now, endedAt: Date? = nil, sets: [WorkoutSet] = []) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sets = sets
    }

    var isActive: Bool { endedAt == nil }

    var totalVolume: Double {
        sets.reduce(0) { $0 + $1.volume }
    }

    var dayLabel: String {
        formatWorkoutDayLabel(endedAt ?? startedAt)
    }
}

struct WorkoutDaySummary: Identifiable, Equatable {
    let id: Date
    let sessions: [WorkoutSession]

    var setCount: Int { sessions.reduce(0) { $0 + $1.sets.count } }
    var totalVolume: Double { sessions.reduce(0) { $0 + $1.totalVolume } }
    var displayDate: String { formatWorkoutDayLabel(id) }
}

struct ExercisePersonalBest: Equatable {
    let weight: Double
    let reps: Int
    let date: Date
}

enum GymExercise: String, CaseIterable, Identifiable, Codable {
    case benchPress = "Bench Press"
    case squat = "Squat"
    case deadlift = "Deadlift"
    case overheadPress = "Overhead Press"
    case barbellRow = "Barbell Row"
    case inclinePress = "Incline Press"
    case pullUp = "Pull-up"
    case legPress = "Leg Press"
    case curl = "Bicep Curl"
    case tricepPushdown = "Tricep Pushdown"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .benchPress, .inclinePress: return "figure.strengthtraining.traditional"
        case .squat, .legPress: return "figure.strengthtraining.functional"
        case .deadlift: return "figure.cooldown"
        case .overheadPress: return "figure.arms.open"
        case .barbellRow, .pullUp: return "figure.climbing"
        case .curl, .tricepPushdown: return "dumbbell.fill"
        }
    }
}

@MainActor
final class WorkoutManager: ObservableObject {
    static let shared = WorkoutManager()

    @Published private(set) var activeSession: WorkoutSession?
    @Published private(set) var history: [WorkoutSession] = []
    @Published var draftExercise: GymExercise = .benchPress
    @Published var draftWeight: Double = 135
    @Published var draftReps: Int = 8

    private let historyKey = "notchpro.workout.history.v1"
    private let activeKey = "notchpro.workout.active.v1"
    private let maxStoredSessions = 90
    private let maxSetsPerSession = 80
    private var persistTask: Task<Void, Never>?

    var isActive: Bool { activeSession?.isActive == true }

    var activeSetCount: Int {
        activeSession?.sets.count ?? 0
    }

    var todayVolume: Double {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let todaySessions = history.filter { $0.startedAt >= startOfDay }
        let activeVolume = activeSession?.totalVolume ?? 0
        return todaySessions.reduce(0) { $0 + $1.totalVolume } + activeVolume
    }

    var sessionsThisWeek: Int {
        guard let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: .now) else { return 0 }
        let completed = history.filter { ($0.endedAt ?? $0.startedAt) >= weekStart }.count
        return completed + (isActive ? 1 : 0)
    }

    var lastSet: WorkoutSet? {
        activeSession?.sets.last ?? history.first?.sets.last
    }

    private init() {
        loadHistory()
        restoreActiveSession()
        applySuggestedDraft(for: draftExercise)
    }

    func startIfEnabled() {}

    func stop() {}

    func startWorkout() {
        guard activeSession == nil else { return }
        activeSession = WorkoutSession()
        schedulePersistActiveSession()
    }

    func endWorkout() {
        guard var session = activeSession else { return }
        session.endedAt = .now
        if !session.sets.isEmpty {
            history.insert(session, at: 0)
            trimHistory()
            saveHistory()
        }
        activeSession = nil
        clearActiveSessionStorage()
    }

    func addSet(exercise: GymExercise? = nil, weight: Double? = nil, reps: Int? = nil) {
        if activeSession == nil {
            startWorkout()
        }
        guard var session = activeSession, session.isActive else { return }

        let parsedWeight = weight ?? draftWeight
        let parsedReps = reps ?? draftReps
        guard parsedWeight > 0, parsedReps > 0 else { return }

        let name = (exercise ?? draftExercise).rawValue
        session.sets.append(
            WorkoutSet(exerciseName: name, weight: parsedWeight, reps: parsedReps)
        )
        if session.sets.count > maxSetsPerSession {
            session.sets.removeFirst(session.sets.count - maxSetsPerSession)
        }
        activeSession = session
        draftWeight = parsedWeight
        draftReps = parsedReps
        schedulePersistActiveSession()
    }

    func repeatLastSet() {
        guard let last = lastSet else { return }
        addSet(
            exercise: GymExercise(rawValue: last.exerciseName) ?? draftExercise,
            weight: last.weight,
            reps: last.reps
        )
    }

    func removeLastSet() {
        guard var session = activeSession, !session.sets.isEmpty else { return }
        session.sets.removeLast()
        activeSession = session
        schedulePersistActiveSession()
    }

    func selectExercise(_ exercise: GymExercise) {
        draftExercise = exercise
        applySuggestedDraft(for: exercise)
    }

    func setDraftWeight(_ weight: Double) {
        draftWeight = max(0, (weight * 10).rounded() / 10)
        schedulePersistActiveSession()
    }

    func adjustDraftWeight(by delta: Double) {
        draftWeight = max(0, (draftWeight + delta * 10).rounded() / 10)
        schedulePersistActiveSession()
    }

    func adjustDraftReps(by delta: Int) {
        draftReps = max(1, min(99, draftReps + delta))
        schedulePersistActiveSession()
    }

    func weightPickerOptions() -> [Double] {
        var options = Set(recentWeights(limit: 8))
        let center = max(draftWeight, 45)
        let low = max(2.5, center - 30)
        let high = center + 30
        var weight = (low * 2).rounded() / 2
        while weight <= high {
            options.insert((weight * 10).rounded() / 10)
            weight += 2.5
        }
        return options.sorted()
    }

    func recentWeights(for exerciseName: String? = nil, limit: Int = 8) -> [Double] {
        var seen: [Double] = []
        let allSessions = ([activeSession].compactMap { $0 }) + history
        for session in allSessions {
            for set in session.sets.reversed() {
                if let exerciseName, set.exerciseName != exerciseName { continue }
                let rounded = (set.weight * 10).rounded() / 10
                if !seen.contains(rounded) {
                    seen.append(rounded)
                }
                if seen.count >= limit { return seen }
            }
        }
        return seen
    }

    func historyByDay(limit: Int = 30) -> [WorkoutDaySummary] {
        var grouped: [Date: [WorkoutSession]] = [:]
        for session in history {
            let day = Calendar.current.startOfDay(for: session.endedAt ?? session.startedAt)
            grouped[day, default: []].append(session)
        }
        if let active = activeSession, !active.sets.isEmpty {
            let day = Calendar.current.startOfDay(for: active.startedAt)
            grouped[day, default: []].insert(active, at: 0)
        }
        return grouped.keys
            .sorted(by: >)
            .prefix(limit)
            .map { day in
                WorkoutDaySummary(
                    id: day,
                    sessions: grouped[day]?.sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) } ?? []
                )
            }
    }

    func personalBest(for exerciseName: String) -> ExercisePersonalBest? {
        var best: ExercisePersonalBest?
        let allSessions = history + (activeSession.map { [$0] } ?? [])

        for session in allSessions {
            for set in session.sets where set.exerciseName == exerciseName {
                let candidate = ExercisePersonalBest(
                    weight: set.weight,
                    reps: set.reps,
                    date: set.completedAt
                )
                if let current = best {
                    if candidate.weight > current.weight
                        || (candidate.weight == current.weight && candidate.reps > current.reps) {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
        }
        return best
    }

    func lastLoggedSet(for exerciseName: String) -> WorkoutSet? {
        for session in ([activeSession].compactMap { $0 }) + history {
            if let match = session.sets.last(where: { $0.exerciseName == exerciseName }) {
                return match
            }
        }
        return nil
    }

    func setsGroupedByExercise() -> [(name: String, sets: [WorkoutSet])] {
        guard let sets = activeSession?.sets else { return [] }
        var order: [String] = []
        var grouped: [String: [WorkoutSet]] = [:]
        for set in sets {
            if grouped[set.exerciseName] == nil { order.append(set.exerciseName) }
            grouped[set.exerciseName, default: []].append(set)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    func applySuggestedDraft(for exercise: GymExercise) {
        if let recent = lastLoggedSet(for: exercise.rawValue) {
            draftWeight = recent.weight
            draftReps = recent.reps
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data)
        else { return }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    private func restoreActiveSession() {
        guard let data = UserDefaults.standard.data(forKey: activeKey),
              let session = try? JSONDecoder().decode(WorkoutSession.self, from: data),
              session.isActive
        else { return }
        activeSession = session
        if let last = session.sets.last,
           let exercise = GymExercise(rawValue: last.exerciseName) {
            draftExercise = exercise
            draftWeight = last.weight
            draftReps = last.reps
        }
    }

    private func schedulePersistActiveSession() {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            persistActiveSessionNow()
        }
    }

    private func persistActiveSessionNow() {
        guard let session = activeSession, session.isActive else {
            clearActiveSessionStorage()
            return
        }
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: activeKey)
    }

    private func clearActiveSessionStorage() {
        UserDefaults.standard.removeObject(forKey: activeKey)
    }

    private func trimHistory() {
        if history.count > maxStoredSessions {
            history = Array(history.prefix(maxStoredSessions))
        }
    }
}

func formatWorkoutWeight(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
        ? String(format: "%.0f", value)
        : String(format: "%.1f", value)
}

func formatWorkoutVolume(_ value: Double) -> String {
    if value >= 1000 { return String(format: "%.1fk lb", value / 1000) }
    return String(format: "%.0f lb", value)
}

func formatWorkoutDayLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}
