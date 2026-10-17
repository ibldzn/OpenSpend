import Foundation

enum FilterPeriod: String, Codable, CaseIterable, Identifiable {
    case today, thisWeek, thisMonth, thisYear, allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .thisYear: "This Year"
        case .allTime: "All Time"
        }
    }

    var spentTitle: String {
        switch self {
        case .today: "Spent Today"
        case .thisWeek: "Spent This Week"
        case .thisMonth: "Spent This Month"
        case .thisYear: "Spent This Year"
        case .allTime: "Spent All Time"
        }
    }

    /// nil = unbounded (all time).
    func interval(now: Date = Date(), weekStart: WeekStartDay = Settings.weekStartDay) -> DateInterval? {
        let cal = Calendar.withWeekStart(weekStart)
        let component: Calendar.Component
        switch self {
        case .today: component = .day
        case .thisWeek: component = .weekOfYear
        case .thisMonth: component = .month
        case .thisYear: component = .year
        case .allTime: return nil
        }
        return cal.dateInterval(of: component, for: now)
    }

    func contains(_ date: Date, now: Date = Date()) -> Bool {
        guard let i = interval(now: now) else { return true }
        return date >= i.start && date < i.end
    }
}

enum WeekStartDay: String, CaseIterable, Identifiable {
    case sunday, monday
    var id: String { rawValue }
    var title: String { self == .sunday ? "Sunday" : "Monday" }
}

extension Calendar {
    static func withWeekStart(_ day: WeekStartDay) -> Calendar {
        var cal = Calendar.current
        cal.firstWeekday = day == .sunday ? 1 : 2
        return cal
    }
}
