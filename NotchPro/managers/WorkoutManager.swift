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
        "\(Int(weight))×\(reps)"
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
}

enum GymExercise: String, CaseIterable, Identifiable {
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
    @Published var draftWeight: String = ""
    @Published var draftReps: String = "8"

    private let storageKey = "notchpro.workout.history.v1"

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

    var lastSet: WorkoutSet? {
        activeSession?.sets.last ?? history.first?.sets.last
    }

    private init() {
        loadHistory()
    }

    func startIfEnabled() {}

    func stop() {}

    func startWorkout() {
        guard activeSession == nil else { return }
        activeSession = WorkoutSession()
    }

    func endWorkout() {
        guard var session = activeSession else { return }
        session.endedAt = .now
        history.insert(session, at: 0)
        trimHistory()
        saveHistory()
        activeSession = nil
    }

    func addSet(exercise: GymExercise? = nil, weight: Double? = nil, reps: Int? = nil) {
        if activeSession == nil {
            startWorkout()
        }
        guard var session = activeSession, session.isActive else { return }

        let parsedWeight = weight ?? Double(draftWeight.replacingOccurrences(of: ",", with: ".")) ?? 0
        let parsedReps = reps ?? Int(draftReps) ?? 0
        guard parsedWeight > 0, parsedReps > 0 else { return }

        let name = (exercise ?? draftExercise).rawValue
        session.sets.append(
            WorkoutSet(exerciseName: name, weight: parsedWeight, reps: parsedReps)
        )
        activeSession = session
        draftWeight = formatWeight(parsedWeight)
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
        activeSession = session.sets.isEmpty ? nil : session
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

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data)
        else { return }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func trimHistory() {
        if history.count > 60 {
            history = Array(history.prefix(60))
        }
    }

    private func formatWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
