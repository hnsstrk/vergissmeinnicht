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
    /// Native Taskwarrior-Abhängigkeits-Reports (`+BLOCKED`/`+BLOCKING`/`+UNBLOCKED`).
    /// `isBlocked`/`isBlocking` werden in Rust über `dependency_map` berechnet und auf
    /// `TaskInfo` annotiert — `matches` testet hier nur das vorab gesetzte Flag, sodass
    /// die zentrale per-Task-Filterlogik intakt bleibt (Karpathy 3).
    case blocked
    case blocking
    case unblocked
    case project(String)
    case tag(String)
    /// Gespeicherte Suche. Wird gleichzeitig mit `searchQuery` gesetzt; die
    /// Filter-Logik selbst delegiert an die Suche (siehe `visibleTasks`), `matches`
    /// liefert hier nur `true`, damit die Sidebar-Selektion eindeutig auf der
    /// Saved-Search-Zeile sitzt (kein Doppel-Highlight mit „Alle").
    case savedSearch(UUID)

    /// Zentrale Filter-Logik. Sidebar-Counts UND ViewModel-Sicht nutzen
    /// diese Funktion, damit nichts driften kann (Karpathy 3).
    ///
    /// `.recurring`-Tasks (Master-Vorlagen) brauchen keine explizite Behandlung:
    /// alle actionable Filter (`.todo`, `.today`, `.inbox`, `.overdue`, `.dueSoon`,
    /// `.upcoming`, `.waiting`) gatten bereits auf `task.status == .pending`, das
    /// `.recurring` ausschließt. `.all`, `.project` und `.tag` zeigen `.recurring`
    /// automatisch, da sie keinen Status-Gate haben — genau das gewünschte Verhalten.
    func matches(_ task: TaskInfo, now: Date, dueSoonDays: Int) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            // "Heute machbar": pending + nicht versteckt + (überfällig ODER fällig heute
            // ODER scheduled heute/vorbei und kein due).
            guard task.status == .pending,
                  !Self.isWaiting(task, now: now),
                  !Self.isUpcoming(task, now: now)
            else { return false }
            let cal = Calendar.current
            if let due = task.due {
                let dueDate = Date(timeIntervalSince1970: TimeInterval(due))
                // Strikt vor Mitternacht des Folgetags: heute fällige (Ende des Tages =
                // 23:59:59) und überfällige Tasks zählen, ein exakt auf 00:00 morgen
                // fallender `due` gehört dagegen zu „morgen", nicht „heute".
                return dueDate < cal.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
            }
            // Kein `due`, aber `scheduled` gesetzt: der `!isUpcoming`-Guard oben hat
            // bereits alles mit `scheduled > now` ausgeschlossen, ein vorhandenes
            // `scheduled` liegt also zwangsläufig heute oder in der Vergangenheit —
            // genau die „heute machbar"-Tasks ohne Deadline. Taskwarrior-natives
            // `scheduled:today` ist der manuelle „für heute einplanen"-Hebel (#1).
            return task.scheduled != nil
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
        case .blocked:
            // +BLOCKED: hängt von ≥1 noch pending Task ab.
            return task.status == .pending && task.isBlocked
        case .blocking:
            // +BLOCKING: ≥1 anderer pending Task hängt von diesem ab.
            return task.status == .pending && task.isBlocking
        case .unblocked:
            // +UNBLOCKED: pending und nicht blockiert. Kein eigenes Flag nötig —
            // abgeleitet aus dem Pending-Status und `!isBlocked`.
            return task.status == .pending && !task.isBlocked
        case .project(let name):
            return task.project == name
        case .tag(let name):
            return task.tags.contains(name)
        case .savedSearch:
            // Inhalt liefert die parallel gesetzte `searchQuery`. Kommt der Filter
            // ohne aktive Query an, zeigen wir bewusst alles statt nichts.
            return true
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
    /// Wenn `true`, werden erledigte Tasks aus der sichtbaren Liste ausgeblendet.
    var hideCompleted: Bool = false

    /// Filtert nach `activeFilter` + `searchQuery` + `hideCompleted` und sortiert
    /// gemäß `sortOrder` + `sortAscending`.
    ///
    /// Mit einer aktiven Suche wechselt der Scope: Sidebar-Filter und
    /// `hideCompleted` werden ignoriert, damit die Suche bestandsweit arbeitet
    /// und auch erledigte Tasks außerhalb der aktuellen Sidebar-Auswahl findet.
    func visibleTasks(from tasks: [TaskInfo], now: Date = Date()) -> [TaskInfo] {
        let filtered: [TaskInfo]
        if let query = parsedSearchQuery() {
            filtered = tasks.filter { matches($0, query: query) }
        } else {
            filtered = tasks
                .filter { activeFilter.matches($0, now: now, dueSoonDays: dueSoonDays) }
                .filter { hideCompleted ? $0.status != .completed : true }
        }
        let sorted = filtered.sorted { lhs, rhs in sortComparator(lhs, rhs) }
        return sortAscending ? sorted : sorted.reversed()
    }

    /// Projekte aus dem aktiven Task-Pool (Pending + Recurring-Master), alphabetisch.
    /// Completed werden ignoriert, damit abgeräumte Projekte nicht ewig in der Sidebar
    /// bleiben. Recurring zählt mit, sonst wäre ein Projekt mit ausschließlich
    /// Recurring-Master über die Sidebar nicht erreichbar.
    /// Static, damit QuickCaptureSheet ohne ViewModel-Instanz darauf zugreifen kann (C2).
    static func projects(from tasks: [TaskInfo]) -> [String] {
        let set = Set(tasks.filter { isActive($0) }.compactMap { $0.project })
        return set.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    /// Tags aus dem aktiven Task-Pool (Pending + Recurring-Master), alphabetisch.
    /// Static, damit QuickCaptureSheet ohne ViewModel-Instanz darauf zugreifen kann (C2).
    static func tags(from tasks: [TaskInfo]) -> [String] {
        let set = Set(tasks.filter { isActive($0) }.flatMap { $0.tags })
        return set.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    private static func isActive(_ task: TaskInfo) -> Bool {
        task.status == .pending || task.status == .recurring
    }

    // MARK: - Suche

    /// Geparste Suchanfrage. Alle Bedingungen sind AND-verknüpft.
    private struct ParsedQuery {
        var freeTerms: [String] = []
        var projects: [String] = []
        var tags: [String] = []
        var statuses: [TaskStatus] = []
    }

    /// Parst `searchQuery` in ein typisiertes Modell oder gibt `nil` zurück,
    /// wenn die Eingabe leer ist. Operatoren: `project:`, `tag:`, `status:`
    /// jeweils mit deutschen Aliasen (`projekt:`, `status:offen` …). Werte mit
    /// Leerzeichen können in doppelten Anführungszeichen stehen.
    private func parsedSearchQuery() -> ParsedQuery? {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var result = ParsedQuery()
        for token in tokenize(trimmed) {
            if let (key, value) = splitOperator(token) {
                switch key.lowercased() {
                case "project", "projekt":
                    result.projects.append(value)
                case "tag":
                    result.tags.append(value)
                case "status":
                    if let status = parseStatus(value) {
                        result.statuses.append(status)
                    } else {
                        // Unbekannter Status-Wert → als Freitext werten, damit der
                        // User nicht stumm leere Ergebnisse bekommt.
                        result.freeTerms.append(token)
                    }
                default:
                    // Unbekannter Operator-Key → kompletter Token als Freitext.
                    result.freeTerms.append(token)
                }
            } else {
                result.freeTerms.append(token)
            }
        }
        return result
    }

    private func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for char in input {
            if char == "\"" {
                inQuotes.toggle()
                continue
            }
            if char.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll()
                }
                continue
            }
            current.append(char)
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Splittet an erstem `:` und liefert (key, value), sofern beide nicht leer sind.
    private func splitOperator(_ token: String) -> (String, String)? {
        guard let colon = token.firstIndex(of: ":") else { return nil }
        let key = String(token[..<colon])
        let value = String(token[token.index(after: colon)...])
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key, value)
    }

    private func parseStatus(_ value: String) -> TaskStatus? {
        switch value.lowercased() {
        case "pending", "offen", "open":           return .pending
        case "completed", "done", "erledigt":      return .completed
        case "deleted", "gelöscht", "geloescht":   return .deleted
        case "recurring", "wiederkehrend":         return .recurring
        default:                                    return nil
        }
    }

    private func matches(_ task: TaskInfo, query: ParsedQuery) -> Bool {
        if !query.statuses.isEmpty, !query.statuses.contains(task.status) {
            return false
        }
        for project in query.projects {
            guard let taskProject = task.project,
                  taskProject.localizedCaseInsensitiveCompare(project) == .orderedSame
            else { return false }
        }
        for tag in query.tags {
            let hit = task.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            if !hit { return false }
        }
        guard !query.freeTerms.isEmpty else { return true }
        let haystacks = freeTextHaystacks(for: task)
        for term in query.freeTerms {
            let hit = haystacks.contains { $0.localizedCaseInsensitiveContains(term) }
            if !hit { return false }
        }
        return true
    }

    /// Alle Felder, in denen freier Suchtext suchen darf.
    private func freeTextHaystacks(for task: TaskInfo) -> [String] {
        var haystacks: [String] = [task.description]
        if let project = task.project { haystacks.append(project) }
        if !task.tags.isEmpty { haystacks.append(task.tags.joined(separator: " ")) }
        if !task.annotations.isEmpty {
            haystacks.append(task.annotations.map(\.description).joined(separator: " "))
        }
        return haystacks
    }

    // MARK: - Sortierung

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
