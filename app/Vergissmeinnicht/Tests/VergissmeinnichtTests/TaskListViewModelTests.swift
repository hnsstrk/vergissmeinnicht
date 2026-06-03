import XCTest
import VergissmeinnichtKit
@testable import Vergissmeinnicht

/// Tests für die zentrale Filter-/Sortier-/Suchlogik (#7). Alle drei sind reine
/// Funktionen auf `TaskInfo` bzw. dem `@MainActor`-`TaskListViewModel` — kein Store
/// nötig. `SidebarFilter.matches` liest `isBlocked`/`isBlocking` als vorab gesetzte
/// Flags (die echte Dependency-Map-Berechnung lebt im Kit-Layer und ist dort
/// getestet), daher werden sie hier direkt auf den Fixtures gesetzt.
@MainActor
final class TaskListViewModelTests: XCTestCase {

    /// Fester Bezugszeitpunkt: 19.06.2026, 12:00 UTC. Alle relativen due/wait/
    /// scheduled-Werte werden gegen diesen `now` gerechnet — zeitzonen-stabil.
    private let now = Date(timeIntervalSince1970: 1_781_870_400) // 2026-06-19T12:00:00Z

    private func ts(_ offsetDays: Double) -> Int64 {
        Int64(now.timeIntervalSince1970 + offsetDays * 86_400)
    }

    /// TaskInfo-Fabrik mit Defaults — nur die relevanten Felder werden je Test gesetzt.
    private func task(
        uuid: String = UUID().uuidString,
        description: String = "Task",
        project: String? = nil,
        tags: [String] = [],
        due: Int64? = nil,
        status: TaskStatus = .pending,
        entry: Int64? = nil,
        workingSetId: UInt32? = nil,
        priority: String? = nil,
        annotations: [AnnotationInfo] = [],
        wait: Int64? = nil,
        recur: String? = nil,
        scheduled: Int64? = nil,
        depends: [String] = [],
        isBlocked: Bool = false,
        isBlocking: Bool = false
    ) -> TaskInfo {
        TaskInfo(
            uuid: uuid, description: description, project: project, tags: tags,
            due: due, status: status, entry: entry, workingSetId: workingSetId,
            priority: priority, annotations: annotations, wait: wait, recur: recur,
            scheduled: scheduled, depends: depends, isBlocked: isBlocked, isBlocking: isBlocking
        )
    }

    private func matches(_ filter: SidebarFilter, _ t: TaskInfo) -> Bool {
        filter.matches(t, now: now, dueSoonDays: 7)
    }

    // MARK: - Filter-Matrix

    func testAllMatchesEveryStatus() {
        XCTAssertTrue(matches(.all, task(status: .pending)))
        XCTAssertTrue(matches(.all, task(status: .completed)))
        XCTAssertTrue(matches(.all, task(status: .recurring)))
        XCTAssertTrue(matches(.all, task(status: .deleted)))
    }

    func testTodoOnlyPending() {
        XCTAssertTrue(matches(.todo, task(status: .pending)))
        XCTAssertFalse(matches(.todo, task(status: .completed)))
        XCTAssertFalse(matches(.todo, task(status: .recurring)))
    }

    func testTodoExcludesWaitingAndUpcoming() {
        XCTAssertFalse(matches(.todo, task(wait: ts(1))))        // wartet (Zukunft)
        XCTAssertFalse(matches(.todo, task(scheduled: ts(1))))   // geplant (Zukunft)
        XCTAssertTrue(matches(.todo, task(wait: ts(-1))))        // Wait in Vergangenheit → aktiv
    }

    func testInboxRequiresNoProjectNoTags() {
        XCTAssertTrue(matches(.inbox, task(project: nil, tags: [])))
        XCTAssertFalse(matches(.inbox, task(project: "X")))
        XCTAssertFalse(matches(.inbox, task(tags: ["a"])))
        XCTAssertFalse(matches(.inbox, task(status: .completed)))
    }

    func testOverdueOnlyPastDuePending() {
        XCTAssertTrue(matches(.overdue, task(due: ts(-1))))      // gestern fällig
        XCTAssertFalse(matches(.overdue, task(due: ts(1))))      // morgen fällig
        XCTAssertFalse(matches(.overdue, task(due: nil)))        // kein due
        XCTAssertFalse(matches(.overdue, task(due: ts(-1), status: .completed)))
    }

    func testDueSoonWithinWindow() {
        XCTAssertTrue(matches(.dueSoon, task(due: ts(3))))       // in 3 Tagen, Fenster 7
        XCTAssertFalse(matches(.dueSoon, task(due: ts(10))))     // außerhalb 7-Tage-Fenster
        XCTAssertFalse(matches(.dueSoon, task(due: ts(-1))))     // überfällig, nicht "bald"
    }

    func testUpcomingNeedsFutureScheduled() {
        XCTAssertTrue(matches(.upcoming, task(scheduled: ts(2))))
        XCTAssertFalse(matches(.upcoming, task(scheduled: ts(-2))))
        XCTAssertFalse(matches(.upcoming, task(scheduled: nil)))
    }

    func testWaitingNeedsFutureWait() {
        XCTAssertTrue(matches(.waiting, task(wait: ts(2))))
        XCTAssertFalse(matches(.waiting, task(wait: ts(-2))))
        XCTAssertFalse(matches(.waiting, task(wait: nil)))
    }

    func testProjectAndTagFilters() {
        XCTAssertTrue(matches(.project("Haus"), task(project: "Haus")))
        XCTAssertFalse(matches(.project("Haus"), task(project: "Auto")))
        XCTAssertTrue(matches(.tag("work"), task(tags: ["work", "urgent"])))
        XCTAssertFalse(matches(.tag("work"), task(tags: ["home"])))
    }

    // MARK: - Projekt-Präfix-Filter (#10, Taskwarrior dotted hierarchy)

    func testProjectExactLeafMatch() {
        // Exaktes Blatt: `Work.ClientA` matcht genau dieses Projekt.
        XCTAssertTrue(matches(.project("Work.ClientA"), task(project: "Work.ClientA")))
        XCTAssertFalse(matches(.project("Work.ClientA"), task(project: "Work.ClientB")))
    }

    func testProjectParentIncludesSubprojects() {
        // Auswahl `Work` matcht `Work` selbst UND alle `Work.*`-Subprojekte.
        XCTAssertTrue(matches(.project("Work"), task(project: "Work")))
        XCTAssertTrue(matches(.project("Work"), task(project: "Work.ClientA")))
        XCTAssertTrue(matches(.project("Work"), task(project: "Work.ClientA.Phase1")))
        XCTAssertFalse(matches(.project("Work"), task(project: "Personal")))
    }

    func testProjectPrefixBoundaryDoesNotMatchSibling() {
        // Die `+ "."`-Grenze ist erforderlich: `Work` darf NICHT `Workshop` matchen.
        XCTAssertFalse(matches(.project("Work"), task(project: "Workshop")))
        XCTAssertFalse(matches(.project("Work"), task(project: "Workshop.Tools")))
    }

    func testProjectNilNeverMatches() {
        XCTAssertFalse(matches(.project("Work"), task(project: nil)))
    }

    func testProjectMatchesPredicateDirect() {
        // Geteilter Wahrheitspunkt für Sidebar-Badge UND Hauptliste.
        XCTAssertTrue(SidebarFilter.projectMatches("Work.ClientA", selected: "Work"))
        XCTAssertTrue(SidebarFilter.projectMatches("Work", selected: "Work"))
        XCTAssertFalse(SidebarFilter.projectMatches("Workshop", selected: "Work"))
        XCTAssertFalse(SidebarFilter.projectMatches(nil, selected: "Work"))
    }

    // MARK: - .today inkl. scheduled-Branch (#1)

    func testTodayMatchesOverdueAndDueToday() {
        XCTAssertTrue(matches(.today, task(due: ts(-1))))   // überfällig zählt
        // Fällig heute (innerhalb der heutigen Kalendertages-Grenze): due == now.
        XCTAssertTrue(matches(.today, task(due: Int64(now.timeIntervalSince1970))))
    }

    func testTodayExcludesFutureDue() {
        // Weit in der Zukunft fällig (z.B. +5 Tage) → nicht "heute".
        XCTAssertFalse(matches(.today, task(due: ts(5))))
    }

    func testTodayScheduledTodayOrPastNoDue() {
        // #1: pending, kein due, scheduled heute/vergangen → "heute machbar".
        XCTAssertTrue(matches(.today, task(due: nil, scheduled: ts(-1))))
    }

    func testTodayExcludesFutureScheduledNoDue() {
        // scheduled in der Zukunft → upcoming, nicht heute.
        XCTAssertFalse(matches(.today, task(due: nil, scheduled: ts(3))))
    }

    func testTodayExcludesNoDueNoScheduled() {
        // Kein due, kein scheduled → keine "heute"-Aktion.
        XCTAssertFalse(matches(.today, task(due: nil, scheduled: nil)))
    }

    func testTodayExcludesCompleted() {
        XCTAssertFalse(matches(.today, task(due: ts(-1), status: .completed)))
    }

    // MARK: - Abhängigkeits-Filter (#3)

    func testBlockedReadsFlag() {
        XCTAssertTrue(matches(.blocked, task(isBlocked: true)))
        XCTAssertFalse(matches(.blocked, task(isBlocked: false)))
        XCTAssertFalse(matches(.blocked, task(status: .completed, isBlocked: true)))
    }

    func testBlockingReadsFlag() {
        XCTAssertTrue(matches(.blocking, task(isBlocking: true)))
        XCTAssertFalse(matches(.blocking, task(isBlocking: false)))
    }

    func testUnblockedIsPendingAndNotBlocked() {
        XCTAssertTrue(matches(.unblocked, task(isBlocked: false)))
        XCTAssertFalse(matches(.unblocked, task(isBlocked: true)))
        XCTAssertFalse(matches(.unblocked, task(status: .completed, isBlocked: false)))
    }

    /// Kleiner Dependency-Graph: A blockiert B. Erwartung über die annotierten Flags.
    func testDependencyGraphBlockedBlockingPartition() {
        let a = task(uuid: "A", description: "Fundament", isBlocking: true)
        let b = task(uuid: "B", description: "Wände", depends: ["A"], isBlocked: true)
        XCTAssertTrue(matches(.blocking, a))
        XCTAssertFalse(matches(.blocked, a))
        XCTAssertTrue(matches(.blocked, b))
        XCTAssertFalse(matches(.blocking, b))
        XCTAssertTrue(matches(.unblocked, a))   // A selbst ist nicht blockiert
        XCTAssertFalse(matches(.unblocked, b))  // B ist blockiert
    }

    // MARK: - Sortierung (Stabilität + Tiebreaker)

    // `SortOrder` kollidiert mit `Foundation.SortOrder`, sobald beide Module sichtbar
    // sind (im Test via `@testable import`). Modul-qualifiziert auflösen.
    private func vm(sort: Vergissmeinnicht.SortOrder, ascending: Bool = true) -> TaskListViewModel {
        let m = TaskListViewModel()
        m.sortOrder = sort
        m.sortAscending = ascending
        m.activeFilter = .all
        m.hideCompleted = false
        return m
    }

    func testSortById() {
        let m = vm(sort: .id)
        let pool = [
            task(uuid: "c", workingSetId: 3),
            task(uuid: "a", workingSetId: 1),
            task(uuid: "b", workingSetId: 2),
        ]
        let ids = m.visibleTasks(from: pool, now: now).map(\.workingSetId)
        XCTAssertEqual(ids, [1, 2, 3])
    }

    func testSortByIdNilLast() {
        // Tasks ohne Working-Set-ID (Completed) sortieren nach hinten.
        let m = vm(sort: .id)
        let pool = [
            task(uuid: "x", description: "ohne id", status: .completed, workingSetId: nil),
            task(uuid: "y", description: "mit id", workingSetId: 1),
        ]
        let order = m.visibleTasks(from: pool, now: now).map(\.uuid)
        XCTAssertEqual(order, ["y", "x"])
    }

    func testSortByDescriptionCaseInsensitive() {
        let m = vm(sort: .description)
        let pool = [task(description: "Zebra"), task(description: "apfel"), task(description: "Banane")]
        let order = m.visibleTasks(from: pool, now: now).map(\.description)
        XCTAssertEqual(order, ["apfel", "Banane", "Zebra"])
    }

    func testSortByDueNilLast() {
        let m = vm(sort: .due)
        let pool = [
            task(uuid: "late", due: ts(5)),
            task(uuid: "none", due: nil),
            task(uuid: "early", due: ts(1)),
        ]
        let order = m.visibleTasks(from: pool, now: now).map(\.uuid)
        XCTAssertEqual(order, ["early", "late", "none"])
    }

    func testSortByProjectThenDescriptionTiebreaker() {
        let m = vm(sort: .project)
        let pool = [
            task(uuid: "1", description: "beta", project: "Haus"),
            task(uuid: "2", description: "alpha", project: "Haus"),
            task(uuid: "3", description: "x", project: "Auto"),
        ]
        let order = m.visibleTasks(from: pool, now: now).map(\.uuid)
        // Auto < Haus; innerhalb Haus alpha < beta.
        XCTAssertEqual(order, ["3", "2", "1"])
    }

    func testSortByEntryNewestFirst() {
        let m = vm(sort: .entry)
        let pool = [
            task(uuid: "old", entry: ts(-5)),
            task(uuid: "new", entry: ts(-1)),
        ]
        let order = m.visibleTasks(from: pool, now: now).map(\.uuid)
        XCTAssertEqual(order, ["new", "old"])
    }

    func testSortDescendingReversesOrder() {
        let asc = vm(sort: .description, ascending: true)
        let desc = vm(sort: .description, ascending: false)
        let pool = [task(description: "a"), task(description: "b"), task(description: "c")]
        let ascOrder = asc.visibleTasks(from: pool, now: now).map(\.description)
        let descOrder = desc.visibleTasks(from: pool, now: now).map(\.description)
        XCTAssertEqual(ascOrder, ["a", "b", "c"])
        XCTAssertEqual(descOrder, ["c", "b", "a"])
    }

    func testSortIsDeterministicAcrossRuns() {
        // Gleiche Eingabe → gleiche Reihenfolge (Stabilität).
        let m = vm(sort: .due)
        let pool = [task(uuid: "a", due: ts(1)), task(uuid: "b", due: ts(1)), task(uuid: "c", due: ts(1))]
        let r1 = m.visibleTasks(from: pool, now: now).map(\.uuid)
        let r2 = m.visibleTasks(from: pool, now: now).map(\.uuid)
        XCTAssertEqual(r1, r2)
    }

    // MARK: - Suche

    private func searchVM(_ query: String) -> TaskListViewModel {
        let m = TaskListViewModel()
        m.searchQuery = query
        return m
    }

    func testSearchFreeTextUmlautCaseInsensitive() {
        let m = searchVM("Äpfel")
        let pool = [task(uuid: "hit", description: "äpfel kaufen"), task(uuid: "miss", description: "Birnen")]
        let result = m.visibleTasks(from: pool, now: now).map(\.uuid)
        XCTAssertEqual(result, ["hit"])
    }

    func testSearchProjectOperator() {
        let m = searchVM("project:Haus")
        let pool = [task(uuid: "h", project: "Haus"), task(uuid: "a", project: "Auto")]
        XCTAssertEqual(m.visibleTasks(from: pool, now: now).map(\.uuid), ["h"])
    }

    func testSearchGermanProjektAlias() {
        let m = searchVM("projekt:haus")  // deutscher Alias + Case-Insensitivität
        let pool = [task(uuid: "h", project: "Haus"), task(uuid: "a", project: "Auto")]
        XCTAssertEqual(m.visibleTasks(from: pool, now: now).map(\.uuid), ["h"])
    }

    func testSearchTagOperator() {
        let m = searchVM("tag:work")
        let pool = [task(uuid: "w", tags: ["work"]), task(uuid: "n", tags: ["home"])]
        XCTAssertEqual(m.visibleTasks(from: pool, now: now).map(\.uuid), ["w"])
    }

    func testSearchStatusOperatorGermanAlias() {
        let m = searchVM("status:erledigt")
        let pool = [
            task(uuid: "done", status: .completed),
            task(uuid: "open", status: .pending),
        ]
        XCTAssertEqual(m.visibleTasks(from: pool, now: now).map(\.uuid), ["done"])
    }

    func testSearchQuotedPhrase() {
        let m = searchVM("\"milch kaufen\"")
        let pool = [
            task(uuid: "hit", description: "heute milch kaufen gehen"),
            task(uuid: "miss", description: "milch und brot kaufen"),
        ]
        XCTAssertEqual(m.visibleTasks(from: pool, now: now).map(\.uuid), ["hit"])
    }

    func testSearchAndLogicMultipleTerms() {
        let m = searchVM("milch brot")  // beide Terme müssen matchen (AND)
        let pool = [
            task(uuid: "both", description: "milch und brot"),
            task(uuid: "one", description: "nur milch"),
        ]
        XCTAssertEqual(m.visibleTasks(from: pool, now: now).map(\.uuid), ["both"])
    }

    func testSearchMatchesAnnotations() {
        let m = searchVM("rückruf")
        let pool = [
            task(uuid: "anno", description: "Termin", annotations: [AnnotationInfo(entry: 1, description: "Rückruf vereinbaren")]),
            task(uuid: "plain", description: "Termin"),
        ]
        XCTAssertEqual(m.visibleTasks(from: pool, now: now).map(\.uuid), ["anno"])
    }

    func testSearchUnknownOperatorTreatedAsFreeText() {
        // Unbekannter Operator-Key → kompletter Token als Freitext (kein stilles Leer).
        let m = searchVM("foo:bar")
        let pool = [task(uuid: "hit", description: "enthält foo:bar im Text"), task(uuid: "miss", description: "anders")]
        XCTAssertEqual(m.visibleTasks(from: pool, now: now).map(\.uuid), ["hit"])
    }

    func testSearchScopeIgnoresSidebarFilterAndHideCompleted() {
        // Mit aktiver Suche: bestandsweit, auch erledigte außerhalb der Sidebar-Auswahl.
        let m = searchVM("ziel")
        m.activeFilter = .inbox
        m.hideCompleted = true
        let pool = [
            task(uuid: "done", description: "ziel erreicht", project: "X", status: .completed),
            task(uuid: "open", description: "ziel offen"),
        ]
        let result = Set(m.visibleTasks(from: pool, now: now).map(\.uuid))
        XCTAssertEqual(result, ["done", "open"])
    }
}
