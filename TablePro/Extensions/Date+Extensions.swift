//
//  Date+Extensions.swift
//  TablePro
//
//  Date extensions for relative time display.
//

import Foundation

extension Date {
    /// Returns a human-readable relative time string (e.g., "just now", "2 hours ago", "3 days ago")
    func timeAgoDisplay() -> String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.second, .minute, .hour, .day, .weekOfYear, .month, .year],
            from: self,
            to: now
        )

        if let year = components.year, year >= 1 {
            return year == 1 ? "1 year ago" : "\(year) years ago"
        }

        if let month = components.month, month >= 1 {
            return month == 1 ? "1 month ago" : "\(month) months ago"
        }

        if let week = components.weekOfYear, week >= 1 {
            return week == 1 ? "1 week ago" : "\(week) weeks ago"
        }

        if let day = components.day, day >= 1 {
            return day == 1 ? "yesterday" : "\(day) days ago"
        }

        if let hour = components.hour, hour >= 1 {
            return hour == 1 ? "1 hour ago" : "\(hour) hours ago"
        }

        if let minute = components.minute, minute >= 1 {
            return minute == 1 ? "1 minute ago" : "\(minute) minutes ago"
        }

        return "just now"
    }
}
