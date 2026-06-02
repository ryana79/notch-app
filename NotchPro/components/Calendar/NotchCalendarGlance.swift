//
//  NotchCalendarGlance.swift
//  NotchPro
//

import Defaults
import SwiftUI

extension CalendarManager {
    var nextUpcomingEvent: EventModel? {
        EventListView.filteredEvents(events: events)
            .filter { $0.end > Date() }
            .sorted { $0.start < $1.start }
            .first
    }
}

struct NotchCalendarGlance: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) private var showCalendar

    var body: some View {
        if showCalendar, let event = calendarManager.nextUpcomingEvent {
            NotchProPill(tint: eventColor(for: event)) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(eventColor(for: event))
                        .frame(width: 6, height: 6)
                    Text(timeLabel(for: event))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(event.title)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .frame(maxWidth: 72)
                }
            }
        }
    }

    private func eventColor(for event: EventModel) -> Color {
        Color(nsColor: event.calendar.color)
    }

    private func timeLabel(for event: EventModel) -> String {
        if event.isAllDay { return "All day" }
        if event.eventStatus == .inProgress { return "Now" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.start)
    }
}

struct NotchNextEventCard: View {
    @ObservedObject private var calendarManager = CalendarManager.shared

    var body: some View {
        if let event = calendarManager.nextUpcomingEvent {
            NotchProCard(accent: eventColor(for: event), accentOpacity: 0.25) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: event.type.isReminder ? "checklist" : "calendar")
                            .font(.caption)
                            .foregroundStyle(eventColor(for: event))
                        Text(event.eventStatus == .inProgress ? "Happening now" : "Up next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(timeLabel(for: event))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(eventColor(for: event))
                    }
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } else if Defaults[.showCalendar] {
            NotchProCard {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.checkmark")
                        .foregroundStyle(Color.effectiveAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear schedule")
                            .font(.subheadline.weight(.medium))
                        Text("No upcoming events")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func eventColor(for event: EventModel) -> Color {
        Color(nsColor: event.calendar.color)
    }

    private func timeLabel(for event: EventModel) -> String {
        if event.isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: event.start)
    }
}
