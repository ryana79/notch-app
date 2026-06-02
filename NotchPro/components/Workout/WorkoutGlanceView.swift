//
//  WorkoutGlanceView.swift
//  NotchPro
//

import Defaults
import SwiftUI

struct WorkoutGlanceView: View {
    var body: some View {
        WorkoutPill()
    }
}

struct WorkoutPill: View {
    @ObservedObject private var workout = WorkoutManager.shared
    @Default(.showWorkoutGlance) private var showWorkoutGlance

    var body: some View {
        if showWorkoutGlance, workout.isActive {
            NotchProPill(tint: .orange) {
                HStack(spacing: 5) {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption2)
                        .symbolEffect(.pulse, options: .repeating, value: workout.isActive)
                    Text(workout.elapsedDisplay)
                        .font(.caption.weight(.bold).monospacedDigit())
                    if let last = workout.lastSet {
                        Text("· \(Int(last.weight))×\(last.reps)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .foregroundStyle(.white.opacity(0.92))
            }
        } else if showWorkoutGlance, workout.todayVolume > 0 {
            NotchProPill(tint: .orange) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                    Text(formatVolume(workout.todayVolume))
                        .font(.caption.weight(.bold).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.1fk lb", value / 1000) }
        return String(format: "%.0f lb", value)
    }
}

struct WorkoutExpandedView: View {
    @ObservedObject private var workout = WorkoutManager.shared
    @State private var showExercisePicker = false

    var body: some View {
        NotchProCard(accent: .orange, accentOpacity: 0.28) {
            VStack(alignment: .leading, spacing: 10) {
                headerRow

                if workout.isActive {
                    activeWorkoutContent
                } else {
                    idleContent
                }
            }
        }
        .frame(minWidth: 190)
    }

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gym")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if workout.isActive {
                    Text(workout.elapsedDisplay)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                } else {
                    Text("Weightlifting")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            Spacer()
            if workout.isActive {
                Text(formatVolume(workout.activeSession?.totalVolume ?? 0))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
            }
        }
    }

    @ViewBuilder
    private var activeWorkoutContent: some View {
        if !workout.setsGroupedByExercise().isEmpty {
            VStack(spacing: 5) {
                ForEach(workout.setsGroupedByExercise(), id: \.name) { group in
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        HStack(spacing: 3) {
                            ForEach(group.sets) { set in
                                Text("\(Int(set.weight))×\(set.reps)")
                                    .font(.caption2.monospacedDigit())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }

        logSetRow

        HStack(spacing: 8) {
            Button("Repeat") { workout.repeatLastSet() }
                .buttonStyle(WorkoutChipStyle(tint: .orange))
                .disabled(workout.lastSet == nil)

            Button("Undo") { workout.removeLastSet() }
                .buttonStyle(WorkoutChipStyle(tint: .white))
                .disabled(workout.activeSession?.sets.isEmpty != false)

            Spacer()

            Button("Finish") { workout.endWorkout() }
                .buttonStyle(WorkoutChipStyle(tint: .red))
        }
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if workout.todayVolume > 0 {
                HStack {
                    Text("Today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatVolume(workout.todayVolume))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }

            if let last = workout.lastSet {
                Text("Last: \(last.exerciseName) \(Int(last.weight)) lb × \(last.reps)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                workout.startWorkout()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start workout")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorkoutPrimaryStyle())
        }
    }

    private var logSetRow: some View {
        VStack(spacing: 6) {
            Menu {
                ForEach(GymExercise.allCases) { exercise in
                    Button(exercise.rawValue) { workout.draftExercise = exercise }
                }
            } label: {
                HStack {
                    Image(systemName: workout.draftExercise.symbol)
                    Text(workout.draftExercise.rawValue)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
            }
            .menuStyle(.borderlessButton)

            HStack(spacing: 8) {
                setField(title: "Weight", text: $workout.draftWeight, suffix: "lb")
                setField(title: "Reps", text: $workout.draftReps, suffix: nil)
                Button {
                    workout.addSet()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.orange.opacity(0.85)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func setField(title: String, text: Binding<String>, suffix: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                TextField(title, text: text)
                    .textFieldStyle(.plain)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(width: 44)
                if let suffix {
                    Text(suffix)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
        }
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.1fk lb", value / 1000) }
        return String(format: "%.0f lb", value)
    }
}

private struct WorkoutPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct WorkoutChipStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint == .white ? Color.white.opacity(0.85) : tint)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
