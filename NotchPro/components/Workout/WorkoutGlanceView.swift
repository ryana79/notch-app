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
        if showWorkoutGlance, workout.isActive, let last = workout.lastSet {
            NotchProPill(tint: .orange) {
                HStack(spacing: 5) {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption2)
                    Text("\(last.exerciseName) \(last.displaySummary)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.92))
            }
        } else if showWorkoutGlance, workout.todayVolume > 0 {
            NotchProPill(tint: .orange) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                    Text(formatWorkoutVolume(workout.todayVolume))
                        .font(.caption.weight(.bold).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        } else if showWorkoutGlance {
            NotchProPill(tint: .orange) {
                HStack(spacing: 4) {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption2)
                    Text("Gym")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

struct WorkoutExpandedView: View {
    @ObservedObject private var workout = WorkoutManager.shared
    @State private var showHistory = false
    @State private var isAddSetHovering = false

    var body: some View {
        NotchProCard(accent: .orange, accentOpacity: 0.28) {
            VStack(alignment: .leading, spacing: 8) {
                headerRow
                progressRow

                if workout.isActive, !workout.setsGroupedByExercise().isEmpty {
                    activeSetSummary
                } else if !workout.isActive {
                    idleContent
                }

                logSetRow

                if workout.isActive {
                    activeControls
                }

                if !workout.historyByDay().isEmpty {
                    historySection
                }
            }
        }
    }

    private var headerRow: some View {
        Button {
            if !workout.isActive {
                workout.startWorkout()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Gym")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(workout.isActive ? "Logging sets" : "Weightlifting")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 4)
                if workout.isActive {
                    Text("\(workout.activeSetCount) sets · Today")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                } else {
                    Text("Tap to start")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange.opacity(0.85))
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var progressRow: some View {
        if workout.sessionsThisWeek > 0 || workout.todayVolume > 0 {
            HStack(spacing: 8) {
                if workout.sessionsThisWeek > 0 {
                    Label("\(workout.sessionsThisWeek)/wk", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if workout.todayVolume > 0 {
                    Spacer(minLength: 0)
                    Text(formatWorkoutVolume(workout.todayVolume))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.orange.opacity(0.9))
                }
            }
        }
    }

    @ViewBuilder
    private var activeSetSummary: some View {
        VStack(spacing: 4) {
            ForEach(workout.setsGroupedByExercise(), id: \.name) { group in
                HStack(spacing: 4) {
                    Text(group.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .frame(maxWidth: 72, alignment: .leading)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 3) {
                            ForEach(group.sets) { set in
                                Text(set.displaySummary)
                                    .font(.caption2.monospacedDigit())
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var activeControls: some View {
        HStack(spacing: 6) {
            Button("Repeat") { workout.repeatLastSet() }
                .buttonStyle(WorkoutChipStyle(tint: .orange))
                .disabled(workout.lastSet == nil)

            Button("Undo") { workout.removeLastSet() }
                .buttonStyle(WorkoutChipStyle(tint: .white))
                .disabled(workout.activeSession?.sets.isEmpty != false)

            Spacer(minLength: 0)

            Button("Done") { workout.endWorkout() }
                .buttonStyle(WorkoutChipStyle(tint: .red))
        }
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let last = workout.lastSet {
                Text("Last (\(last.loggedDayLabel)): \(last.exerciseName) \(last.displaySummary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let pr = workout.personalBest(for: workout.draftExercise.rawValue) {
                Text("PR: \(formatWorkoutWeight(pr.weight)) lb × \(pr.reps)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange.opacity(0.85))
            }
        }
    }

    private var logSetRow: some View {
        VStack(spacing: 5) {
            Menu {
                ForEach(GymExercise.allCases) { exercise in
                    Button(exercise.rawValue) { workout.selectExercise(exercise) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: workout.draftExercise.symbol)
                        .font(.caption2)
                    Text(workout.draftExercise.rawValue)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
            }
            .menuStyle(.borderlessButton)

            HStack(spacing: 5) {
                weightStepper
                compactStepper(
                    label: "Reps",
                    value: "\(workout.draftReps)",
                    onDecrement: { workout.adjustDraftReps(by: -1) },
                    onIncrement: { workout.adjustDraftReps(by: 1) }
                )

                Button {
                    if !workout.isActive { workout.startWorkout() }
                    workout.addSet()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2.weight(.bold))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(Color.orange.opacity(isAddSetHovering ? 1 : 0.85))
                                .shadow(
                                    color: .orange.opacity(isAddSetHovering ? 0.55 : 0),
                                    radius: isAddSetHovering ? 8 : 0
                                )
                        )
                        .foregroundStyle(.white)
                        .scaleEffect(isAddSetHovering ? 1.08 : 1)
                }
                .buttonStyle(.plain)
                .disabled(workout.draftWeight <= 0)
                .animation(.smooth(duration: 0.2), value: isAddSetHovering)
                .onHover { isAddSetHovering = $0 }
            }
        }
    }

    private var weightStepper: some View {
        HStack(spacing: 3) {
            stepperButton(systemName: "minus") { workout.adjustDraftWeight(by: -2.5) }
            Menu {
                if !workout.recentWeights(for: workout.draftExercise.rawValue).isEmpty {
                    Section("Recent") {
                        ForEach(workout.recentWeights(for: workout.draftExercise.rawValue), id: \.self) { weight in
                            Button("\(formatWorkoutWeight(weight)) lb") {
                                workout.setDraftWeight(weight)
                            }
                        }
                    }
                }
                Section("Pick weight (lb)") {
                    ForEach(workout.weightPickerOptions(), id: \.self) { weight in
                        Button("\(formatWorkoutWeight(weight)) lb") {
                            workout.setDraftWeight(weight)
                        }
                    }
                }
            } label: {
                VStack(spacing: 0) {
                    Text("Weight")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("\(formatWorkoutWeight(workout.draftWeight)) lb")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)
            stepperButton(systemName: "plus") { workout.adjustDraftWeight(by: 2.5) }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
    }

    private var historySection: some View {
        DisclosureGroup(isExpanded: $showHistory) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(workout.historyByDay()) { day in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(day.displayDate)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer(minLength: 0)
                                Text("\(day.setCount) sets · \(formatWorkoutVolume(day.totalVolume))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(day.sessions) { session in
                                ForEach(session.sets) { set in
                                    Text("\(set.exerciseName) · \(set.displaySummary)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 110)
        } label: {
            Text("Log history")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func compactStepper(
        label: String,
        value: String,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 3) {
            stepperButton(systemName: "minus", action: onDecrement)
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            stepperButton(systemName: "plus", action: onIncrement)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
    }

    private func stepperButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
    }
}

private struct WorkoutChipStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint == .white ? Color.white.opacity(0.85) : tint)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
