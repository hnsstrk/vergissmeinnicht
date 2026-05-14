import Foundation
import SwiftUI
import VergissmeinnichtKit

/// Filter-Modi der Sidebar.
///
/// `all` zeigt alle Tasks inkl. erledigter; `todo` nur Pending; `inbox` Pending ohne
/// Projekt und ohne Tags; `overdue` und `dueSoon` schneiden auf das `due`-Feld der
/// Pending-Liste; `project` und `tag` filtern auf einen konkreten Wert (Status egal,
/// damit man auch erledigte Tasks eines Projekts wiederfindet — aber siehe
/// `showCompletedInGroupedViews` falls das später konfigurierbar werden soll).
enum SidebarFilter: Hashable {
    case all
    case today
    case todo
    case inbox
    case overdue
    case dueSoon
    case upcoming
    case waiting
    case project(String)
    case tag(String)

    /// Zentrale Filter-Logik. Sidebar-Counts UND ViewModel-Sicht nutzen
    /// diese Funktion, damit nichts driften kann (Karpathy 3).
    func matches(_ task: TaskInfo, now: Date, dueSoonDays: Int) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            // „Heute machbar": pending + nicht versteckt + (überfällig ODER fällig heute
            // ODER scheduled heute/vorbei und kein due).
            guard task.status == .pending,
                  !Self.isWaiting(task, now: now),
                  !Self.isUpcoming(task, now: now)
            else { return false }
            let cal = Calendar.current
            if let due = task.due {
                let dueDate = Date(timeIntervalSince1970: TimeInterval(due))
                if dueDate <= cal.startOfDay(for: now).addingTimeInterval(24 * 60 * 60) {
                    return true
                }
            }
            return false
        case .todo:
            return task.status == .pending
                && !Self.isWaiting(task, now: now)
                && !Self.isUpcoming(task, now: now)
        case .inbox:
            return task.status == .pending
                && task.project == nil
                && task.tags.isEmpty
                && !Self.isWaiting(task, now: now)
                && !Self.isUpcoming(task, now: now)
        case .overdue:
            guard task.status == .pending,
                  !Self.isUpcoming(task, now: now),
                  let due = task.due
            else { return false }
            return TimeInterval(due) < now.timeIntervalSince1970
        case .dueSoon:
            guard task.status == .pending,
                  !Self.isUpcoming(task, now: now),
                  let due = task.due
            else { return false }
            let dueSeconds = TimeInterval(due)
            let nowSeconds = now.timeIntervalSince1970
            return dueSeconds >= nowSeconds
                && dueSeconds <= nowSeconds + TimeInterval(dueSoonDays) * 24 * 60 * 60
        case .upcoming:
            return task.status == .pending && Self.isUpcoming(task, now: now)
        case .waiting:
            return task.status == .pending && Self.isWaiting(task, now: now)
        case .project(let name):
            return task.project == name
        case .tag(let name):
            return task.tags.contains(name)
        }
    }

    static func isWaiting(_ task: TaskInfo, now: Date) -> Bool {
        guard let wait = task.wait else { return false }
        return TimeInterval(wait) > now.timeIntervalSince1970
    }

    /// Geplant für die Zukunft — Task hat `scheduled` gesetzt und der Zeitpunkt
    /// liegt nach jetzt.
    static func isUpcoming(_ task: TaskInfo, now: Date) -> Bool {
        guard let scheduled = task.scheduled else { return false }
        return TimeInterval(scheduled) > now.timeIntervalSince1970
    }
}

/// Sortier-Reihenfolge der Task-Liste im Hauptbereich.
enum SortOrder: String, CaseIterable, Identifiable {
    case id, description, entry, due, project

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .id:          return "ID"
        case .description: return "Name"
        case .entry:       return "Angelegt"
        case .due:         return "Fälligkeit"
        case .project:     return "Projekt"
        }
    }
}

/// UI-State für die Task-Liste: Filter (Sidebar-Auswahl), Sortierung, Suche, Selection.
///
/// Die `tasks`-Liste selbst lebt im `AppContainer` (Single Source of Truth);
/// dieses ViewModel hält bewusst nur abgeleiteten UI-State — siehe Karpathy 2.
@MainActor
@Observable
final class TaskListViewModel {
    var searchQuery: String = ""
    /// Multi-Selection-Set für die Hauptliste (macOS List unterstützt Set-Binding).
    var selectedUuids: Set<String> = []
    /// Komfort-Accessor: erste Selection (bzw. nil) — für Single-Action-Pfade.
    var selectedUuid: String? {
        get { selectedUuids.first }
        set {
            if let v = newValue { selectedUuids = [v] } else { selectedUuids.removeAll() }
        }
    }
    var activeFilter: SidebarFilter = .inbox
    var sortOrder: SortOrder = .id
    /// Sortier-Richtung. Default aufsteigend; in `entry` sortieren wir trotzdem
    /// "neueste zuerst", indem die Comparator-Funktion das Vorzeichen anwendet.
    var sortAscending: Bool = true
    /// Anzahl Tage für "Bald fällig" — vom Settings-Pane überschrieben.
    var dueSoonDays: Int = 7

    /// Filtert nach `activeFilter` + `searchQuery` und sortiert gemäß `sortOrder` + `sortAscending`.
    func visibleTasks(from tasks: [TaskInfo], now: Date = Date()) -> [TaskInfo] {
        let filtered = tasks
            .filter { activeFilter.matches($0, now: now, dueSoonDays: dueSoonDays) }
            .filter { matchesSearch($0) }
        let sorted = filtered.sorted(by: sortComparator)
        return sortAscending ? sorted : sorted.reversed()
    }

    /// Projekte aus dem Pending-Pool, alphabetisch. Completed werden ignoriert, damit
    /// abgeräumte Projekte nicht ewig in der Sidebar bleiben.
    func projects(from tasks: [TaskInfo]) -> [String] {
        let set = Set(tasks.filter { $0.status == .pending }.compactMap { $0.project })
        return set.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    /// Tags aus dem Pending-Pool, alphabetisch.
    func tags(from tasks: [TaskInfo]) -> [String] {
        let set = Set(tasks.filter { $0.status == .pending }.flatMap { $0.tags })
        return set.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    // MARK: - Private

    private func matchesSearch(_ task: TaskInfo) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return task.description.localizedCaseInsensitiveContains(query)
    }

    private func sortComparator(_ lhs: TaskInfo, _ rhs: TaskInfo) -> Bool {
        switch sortOrder {
        case .id:
            // Working-Set-IDs sortieren aufsteigend; Tasks ohne ID (Completed) nach hinten.
            switch (lhs.workingSetId, rhs.workingSetId) {
            case (let l?, let r?): return l < r
            case (.some, .none):   return true
            case (.none, .some):   return false
            case (.none, .none):
                return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
            }
        case .description:
            return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
        case .entry:
            // Neueste zuerst.
            switch (lhs.entry, rhs.entry) {
            case (let l?, let r?): return l > r
            case (.some, .none):   return true
            case (.none, .some):   return false
            case (.none, .none):
                return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
            }
        case .due:
            switch (lhs.due, rhs.due) {
            case (let l?, let r?): return l < r
            case (.some, .none):   return true
            case (.none, .some):   return false
            case (.none, .none):
                return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
            }
        case .project:
            switch (lhs.project, rhs.project) {
            case (let l?, let r?):
                let cmp = l.localizedCaseInsensitiveCompare(r)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none):
                return lhs.description.localizedCaseInsensitiveCompare(rhs.description) == .orderedAscending
            }
        }
    }
}
