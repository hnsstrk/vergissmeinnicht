import Foundation
import VergissmeinnichtKit

/// Art einer Zeile im Abhängigkeitsbaum.
enum DependencyTreeRowKind: Equatable {
    /// Hauptzeile eines sichtbaren Tasks (selektierbar, mit Teilbaum).
    case task
    /// Weiteres Vorkommen eines bereits gezeigten Tasks (Diamant) — keine Kinder.
    case reference
    /// Task liegt auf dem aktuellen Pfad (Zyklus, auch Selbstabhängigkeit).
    case cycle
    /// Voraussetzung ist pending, aber durch Filter/Suche nicht sichtbar (Geist, mit Kindern).
    case outside
    /// Voraussetzung ist erledigt und nicht sichtbar, z. B. `hideCompleted` (Geist, mit Kindern).
    case completed
}

/// Abschnitt des Gruppen-Balkens eines Vorfahren in einer Zeile.
struct TreeBar: Equatable {
    /// Erste Nachfahrenzeile der Gruppe (Balken beginnt mit Rundung).
    let isStart: Bool
    /// Letzte Nachfahrenzeile der Gruppe (Balken endet mit Rundung).
    let isEnd: Bool
}

/// Eine Zeile des Abhängigkeitsbaums. `id` ist der Pfad (UUID-Kette mit „/"),
/// damit dieselbe UUID an mehreren Stellen eindeutig in der `List` bleibt.
struct DependencyTreeRow: Identifiable, Equatable {
    let id: String
    let taskUuid: String
    let depth: Int
    let kind: DependencyTreeRowKind
    var hasChildren: Bool
    /// Anzahl verborgener Nachfahrenzeilen, sofern der Knoten zugeklappt ist.
    var hiddenCount: Int
    /// Ein Gruppen-Balken je Vorfahren-Ebene (`depth` Einträge, Index = Ebene des Vorfahren).
    /// Der Balken einer Ebene läuft durch alle Nachfahrenzeilen dieses Vorfahren.
    var bars: [TreeBar]

    /// Pfad-ID der Elternzeile, `nil` bei Wurzeln.
    var parentId: String? {
        guard let slash = id.lastIndex(of: "/") else { return nil }
        return String(id[..<slash])
    }

    /// UUID der Elternzeile (die Voraussetzung), `nil` bei Wurzeln.
    var parentUuid: String? {
        parentId.map { $0.split(separator: "/").last.map(String.init) ?? $0 }
    }
}

/// Ordnet die sichtbare, bereits gefilterte und sortierte Liste als Baum entlang
/// `depends` an. Eltern = Voraussetzung, Kinder = Tasks, die von ihr abhängen —
/// oben steht, was zuerst erledigt werden muss. Nicht sichtbare Voraussetzungen
/// (pending/recurring oder erledigt) erscheinen als „Geister" mit ihren sichtbaren
/// Kindern. Reine Funktion ohne eigene Sortierlogik — Geschwister folgen der Position
/// in `visible`, ein Geist steht direkt vor seinem ersten Kind.
enum DependencyTree {
    static func rows(visible: [TaskInfo], all: [TaskInfo], collapsed: Set<String>) -> [DependencyTreeRow] {
        var byUuid: [String: TaskInfo] = [:]
        for t in all { byUuid[t.uuid] = t }
        var position: [String: Int] = [:]
        for (i, t) in visible.enumerated() where position[t.uuid] == nil {
            position[t.uuid] = i
        }

        var ghosts: [String: DependencyTreeRowKind] = [:]
        var ghostPosition: [String: Int] = [:]
        // Kinder je Voraussetzung; Iteration in Listenreihenfolge ordnet sie von selbst.
        var childrenOf: [String: [String]] = [:]
        var hasParentNode = Set<String>()
        var hasVisibleParent = Set<String>()
        for (i, t) in visible.enumerated() where position[t.uuid] == i {
            var seen = Set<String>()
            for dep in t.depends where seen.insert(dep).inserted {
                if position[dep] == nil {
                    guard let info = byUuid[dep] else { continue }
                    switch info.status {
                    case .completed: ghosts[dep] = .completed
                    case .pending, .recurring: ghosts[dep] = .outside
                    case .deleted: continue
                    }
                    ghostPosition[dep] = min(ghostPosition[dep] ?? i, i)
                }
                childrenOf[dep, default: []].append(t.uuid)
                if dep != t.uuid {
                    hasParentNode.insert(t.uuid)
                    if position[dep] != nil { hasVisibleParent.insert(t.uuid) }
                }
            }
        }

        // Wurzeln: Knoten ohne Elternknoten. Geist-Sortschlüssel = Position des ersten Kindes − 0,5.
        var rootKeys: [(key: Double, uuid: String)] = []
        for (uuid, i) in position where !hasParentNode.contains(uuid) {
            rootKeys.append((Double(i), uuid))
        }
        for (uuid, i) in ghostPosition {
            rootKeys.append((Double(i) - 0.5, uuid))
        }
        rootKeys.sort { a, b in a.key != b.key ? a.key < b.key : a.uuid < b.uuid }

        var builder = Builder(childrenOf: childrenOf, ghosts: ghosts, hasVisibleParent: hasVisibleParent)
        for root in rootKeys {
            builder.visit(uuid: root.uuid, parentPath: nil, depth: 0)
        }
        // Reiner Zyklus ohne Wurzel: übrige Knoten in Sortierreihenfolge als Wurzeln.
        for t in visible where !builder.visited.contains(t.uuid) {
            builder.visit(uuid: t.uuid, parentPath: nil, depth: 0)
        }
        return builder.finalRows(collapsed: collapsed)
    }

    /// Pre-Order-Aufbau. Zuklappen wirkt erst danach (`finalRows`), damit das
    /// „erste Vorkommen" eines Tasks nicht vom Klappzustand abhängt.
    private struct Builder {
        let childrenOf: [String: [String]]
        let ghosts: [String: DependencyTreeRowKind]
        /// Sichtbare Tasks mit mindestens einer sichtbaren Voraussetzung: ihr volles
        /// Vorkommen steht unter dieser, unter Geistern nur ein Verweis.
        let hasVisibleParent: Set<String>
        var visited = Set<String>()
        var path: [String] = []
        var full: [DependencyTreeRow] = []

        mutating func visit(uuid: String, parentPath: String?, depth: Int) {
            let id = parentPath.map { $0 + "/" + uuid } ?? uuid
            let kind = ghosts[uuid] ?? .task
            if kind == .task { visited.insert(uuid) }
            path.append(uuid)
            let rowIndex = full.count
            full.append(DependencyTreeRow(
                id: id, taskUuid: uuid, depth: depth, kind: kind,
                hasChildren: false, hiddenCount: 0, bars: []
            ))

            // Kinder sind immer sichtbare Tasks.
            let kids = childrenOf[uuid] ?? []
            for kid in kids {
                let kidId = id + "/" + kid
                if path.contains(kid) {
                    emit(kidId, kid, depth + 1, .cycle)
                } else if visited.contains(kid) || (kind != .task && hasVisibleParent.contains(kid)) {
                    emit(kidId, kid, depth + 1, .reference)
                } else {
                    visit(uuid: kid, parentPath: id, depth: depth + 1)
                }
            }
            path.removeLast()

            if full.count - rowIndex > 1 {
                full[rowIndex].hasChildren = true
            }
        }

        private mutating func emit(
            _ id: String, _ uuid: String, _ depth: Int, _ kind: DependencyTreeRowKind
        ) {
            full.append(DependencyTreeRow(
                id: id, taskUuid: uuid, depth: depth, kind: kind,
                hasChildren: false, hiddenCount: 0, bars: []
            ))
        }

        /// Wendet den Klappzustand an: Nachfahren zugeklappter Knoten entfallen,
        /// `hiddenCount` nennt ihre Anzahl. Danach werden die Gruppen-Balken berechnet.
        func finalRows(collapsed: Set<String>) -> [DependencyTreeRow] {
            var result: [DependencyTreeRow] = []
            var skipDepth: Int?
            var i = 0
            while i < full.count {
                let r = full[i]
                if let s = skipDepth {
                    if r.depth > s { i += 1; continue }
                    skipDepth = nil
                }
                if r.hasChildren, collapsed.contains(r.id) {
                    var collapsedRow = r
                    var j = i + 1
                    while j < full.count, full[j].depth > r.depth { j += 1 }
                    collapsedRow.hiddenCount = j - i - 1
                    result.append(collapsedRow)
                    skipDepth = r.depth
                } else {
                    result.append(r)
                }
                i += 1
            }
            return withBars(result)
        }

        /// Balken je Vorfahren-Ebene k: Eine Zeile ist erste Nachfahrenzeile von Ebene k,
        /// wenn die Zeile davor Tiefe k hat (der Vorfahr selbst), und letzte, wenn die
        /// folgende Zeile nicht tiefer als k liegt.
        private func withBars(_ rows: [DependencyTreeRow]) -> [DependencyTreeRow] {
            var result = rows
            for i in rows.indices {
                let depth = rows[i].depth
                result[i].bars = (0..<depth).map { level in
                    TreeBar(
                        isStart: i > 0 && rows[i - 1].depth == level,
                        isEnd: i + 1 >= rows.count || rows[i + 1].depth <= level
                    )
                }
            }
            return result
        }
    }
}
