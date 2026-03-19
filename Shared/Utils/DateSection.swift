mport Foundation

enum DateSection: Hashable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case month(year: Int, month: Int)

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .month(let year, let month):
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            if let date = Calendar.current.date(from: comps) {
                return formatter.string(from: date)
            }
            return "\(month)/\(year)"
        }
    }

    static func section(for date: Date) -> DateSection {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        if let weekInterval = cal.dateInterval(of: .weekOfYear, for: Date()),
           weekInterval.contains(date) {
            return .thisWeek
        }
        if cal.isDate(date, equalTo: Date(), toGranularity: .month) {
            return .thisMonth
        }
        let comps = cal.dateComponents([.year, .month], from: date)
        return .month(year: comps.year!, month: comps.month!)
    }

    // Groups pre-sorted (newest-first) items into ordered sections.
    // Preserves input order within each section.
    static func group<T>(_ items: [T], by dateKey: (T) -> Date) -> [(DateSection, [T])] {
        var result: [(DateSection, [T])] = []
        for item in items {
            let sec = section(for: dateKey(item))
            if let lastIdx = result.indices.last, result[lastIdx].0 == sec {
                result[lastIdx].1.append(item)
            } else if let existingIdx = result.firstIndex(where: { $0.0 == sec }) {
                result[existingIdx].1.append(item)
            } else {
                result.append((sec, [item]))
            }
        }
        return result
    }
}
