import Foundation
import VergissmeinnichtKit

/// Reine Graph-Logik für `depends`-Kanten.
enum DependencyGraph {
    /// `true`, wenn `task` von `dependsOn` abhängig zu machen einen Zyklus erzeugte:
    /// Selbstbezug, oder `task` ist von `dependsOn` aus über `depends` bereits erreichbar.
    /// Alle Kanten zählen unabhängig vom Status. Terminiert auch bei fremden Zyklen;
    /// unbekannte UUIDs werden übergangen.
    static func wouldCreateCycle(task: String, dependsOn: String, tasks: [TaskInfo]) -> Bool {
        if task == dependsOn { return true }
        var edges: [String: [String]] = [:]
        for t in tasks { edges[t.uuid] = t.depends }
        var visited: Set<String> = [dependsOn]
        var stack = [dependsOn]
        while let current = stack.popLast() {
            for next in edges[current] ?? [] {
                if next == task { return true }
                if visited.insert(next).inserted { stack.append(next) }
            }
        }
        return false
    }
}

/// Kandidaten-Suche für den Abhängigkeits-Picker im Detail.
enum DependencyCandidates {
    static let limit = 12

    /// Pending Tasks, die `task` als Voraussetzung bekommen darf, in der Reihenfolge von
    /// `tasks`. `#12` oder `12` trifft die Working-Set-ID exakt (nicht 120); sonst
    /// Teilstring in Titel oder Projekt, ohne Groß-/Kleinschreibung. Leere Suche liefert
    /// die ersten `limit` Kandidaten. Ausgeschlossen: `task` selbst, bereits verknüpfte
    /// und Zyklus-Erzeuger.
    static func filter(query: String, task: TaskInfo, tasks: [TaskInfo], limit: Int = DependencyCandidates.limit) -> [TaskInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let idQuery: UInt32? = digits.isEmpty || !digits.allSatisfy({ $0.isASCII && $0.isNumber }) ? nil : UInt32(digits)

        var result: [TaskInfo] = []
        for candidate in tasks {
            guard result.count < limit else { break }
            guard candidate.status == .pending,
                  candidate.uuid != task.uuid,
                  !task.depends.contains(candidate.uuid)
            else { continue }
            if !trimmed.isEmpty {
                if trimmed.hasPrefix("#") || idQuery != nil {
                    guard let idQuery, candidate.workingSetId == idQuery else { continue }
                } else {
                    let hit = candidate.description.localizedCaseInsensitiveContains(trimmed)
                        || (candidate.project?.localizedCaseInsensitiveContains(trimmed) ?? false)
                    guard hit else { continue }
                }
            }
            guard !DependencyGraph.wouldCreateCycle(task: task.uuid, dependsOn: candidate.uuid, tasks: tasks) else { continue }
            result.append(candidate)
        }
        return result
    }
}
