import Foundation
import VergissmeinnichtKit

/// Taskwarrior-Dringlichkeit (urgency) mit den Standardkoeffizienten.
///
/// Quelle: https://taskwarrior.org/docs/urgency/ und `src/Task.cpp` (`Task::urgency_*`).
/// Eigene Koeffizienten (`urgency.*.coefficient` der `.taskrc`) kennt die App nicht.
enum Urgency {
    static let next: Double = 15.0
    static let due: Double = 12.0
    static let blocking: Double = 8.0
    static let blocked: Double = -5.0
    static let priorityHigh: Double = 6.0
    static let priorityMedium: Double = 3.9
    static let priorityLow: Double = 1.8
    static let scheduled: Double = 5.0
    static let active: Double = 4.0
    static let age: Double = 2.0
    static let annotations: Double = 1.0
    static let tags: Double = 1.0
    static let project: Double = 1.0
    static let waiting: Double = -3.0

    private static let day: Double = 86_400

    static func score(_ task: TaskInfo, now: Date) -> Double {
        let nowSeconds = now.timeIntervalSince1970
        var score = 0.0

        if task.tags.contains("next") { score += next }
        score += due * dueFactor(task.due, now: nowSeconds)
        if task.isBlocking { score += blocking }
        if task.isBlocked { score += blocked }
        switch task.priority {
        case "H": score += priorityHigh
        case "M": score += priorityMedium
        case "L": score += priorityLow
        default: break
        }
        if let s = task.scheduled, TimeInterval(s) < nowSeconds { score += scheduled }
        if task.isActive { score += active }
        score += age * ageFactor(task.entry, now: nowSeconds)
        score += annotations * countFactor(task.annotations.count)
        score += tags * countFactor(task.tags.count)
        if task.project != nil { score += project }
        if task.status == .pending, let w = task.wait, TimeInterval(w) > nowSeconds { score += waiting }
        return score
    }

    /// Fälligkeit: ab 7 Tagen überfällig 1.0, ab 14 Tagen vor Fälligkeit linear
    /// von 0.2 bis 1.0, davor 0.2.
    private static func dueFactor(_ due: Int64?, now: TimeInterval) -> Double {
        guard let due else { return 0 }
        let days = (now - TimeInterval(due)) / day
        if days >= 7 { return 1.0 }
        if days >= -14 { return (days + 14) * 0.8 / 21 + 0.2 }
        return 0.2
    }

    /// Alter in ganzen Tagen (abgeschnitten) relativ zu 365; ohne `entry` oder darüber 1.0.
    private static func ageFactor(_ entry: Int64?, now: TimeInterval) -> Double {
        guard let entry else { return 1.0 }
        let days = ((now - TimeInterval(entry)) / day).rounded(.towardZero)
        return days > 365 ? 1.0 : days / 365
    }

    private static func countFactor(_ count: Int) -> Double {
        switch count {
        case ..<1: return 0
        case 1: return 0.8
        case 2: return 0.9
        default: return 1.0
        }
    }
}
