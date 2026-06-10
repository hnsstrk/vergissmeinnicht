import XCTest
import VergissmeinnichtKit
@testable import Vergissmeinnicht

/// Ergänzende Unit-Tests für `SidebarFilter.matches(_:now:dueSoonDays:)`.
///
/// Die Kern-Filter-Matrix (inbox, today, todo, overdue, dueSoon, waiting, upcoming,
/// all, project/dotted-hierarchy, tag, blocked/unblocked) ist bereits in
/// `TaskListViewModelTests` abgedeckt, da `SidebarFilter` in `TaskListViewModel.swift`
/// definiert ist. Diese Datei ergänzt Fälle, die dort noch fehlen:
///   - `hideCompleted = true` im `visibleTasks`-Pfad ohne aktive Suche
///   - `savedSearch`-Filter-Verhalten (passt immer, delegiert an searchQuery)
///   - `dueSoonDays`-Grenzwert-Varianten (1 Tag, 0 Tage)
///   - `inbox`-Guard: waiting und upcoming werden ausgeschlossen
@MainActor
final class SidebarFilterTests: XCTestCase {

    /// Fester Bezugszeitpunkt: 2026-07-01T10:00:00Z.
    private let now = Date(timeIntervalSince1970: 1_751_364_000)

    private func ts(_ offsetDays: Double) -> Int64 {
        Int64(now.timeIntervalSince1970 + offsetDays * 86_400)
    }

    private func task(
        uuid: String = UUID().uuidString,
        description: String = "Task",
        project: String? = nil,
        tags: [String] = [],
        due: Int64? = nil,
        status: TaskStatus = .pending,
        wait: Int64? = nil,
        scheduled: Int64? = nil,
        isBlocked: Bool = false,
        isBlocking: Bool = false
    ) -> TaskInfo {
        TaskInfo(
            uuid: uuid, description: description, project: project, tags: tags,
            due: due, status: status, entry: nil, workingSetId: nil,
            priority: nil, annotations: [], wait: wait, recur: nil,
            scheduled: scheduled, depends: [], isBlocked: isBlocked, isBlocking: isBlocking
        )
    }

    // MARK: - hideCompleted via visibleTasks (kein Suchquery)

    func testHideCompletedFiltersCompletedFromVisibleTasks() {
        let vm = TaskListViewModel()
        vm.activeFilter = .all
        vm.hideCompleted = true
        let pool = [
            task(uuid: "done", status: .completed),
            task(uuid: "open", status: .pending),
        ]
        let result = vm.visibleTasks(from: pool, now: now).map(\.uuid)
        XCTAssertEqual(result, ["open"])
    }

    func testHideCompletedFalseShowsCompleted() {
        let vm = TaskListViewModel()
        vm.activeFilter = .all
        vm.hideCompleted = false
        let pool = [
            task(uuid: "done", status: .completed),
            task(uuid: "open", status: .pending),
        ]
        let uuids = Set(vm.visibleTasks(from: pool, now: now).map(\.uuid))
        XCTAssertTrue(uuids.contains("done"))
        XCTAssertTrue(uuids.contains("open"))
    }

    // MARK: - savedSearch gibt immer true zurück (Inhalt kommt via searchQuery)

    func testSavedSearchMatchesAllTasks() {
        let id = UUID()
        let filter = SidebarFilter.savedSearch(id)
        // saved-Search-Filter passt auf jeden Status — Filterung übernimmt die Suche.
        XCTAssertTrue(filter.matches(task(status: .pending), now: now, dueSoonDays: 7))
        XCTAssertTrue(filter.matches(task(status: .completed), now: now, dueSoonDays: 7))
        XCTAssertTrue(filter.matches(task(status: .deleted), now: now, dueSoonDays: 7))
    }

    // MARK: - dueSoonDays-Grenzwert

    func testDueSoonExactBoundaryIncluded() {
        // Task, der genau `dueSoonDays` Tage in der Zukunft fällig ist, gehört noch
        // ins Fenster (≤ nowSeconds + dueSoonDays * 86400).
        let filter = SidebarFilter.dueSoon
        let exactBoundary = task(due: ts(3))
        XCTAssertTrue(filter.matches(exactBoundary, now: now, dueSoonDays: 3))
    }

    func testDueSoonOneDayBeyondBoundaryExcluded() {
        let filter = SidebarFilter.dueSoon
        let beyondBoundary = task(due: ts(4))
        XCTAssertFalse(filter.matches(beyondBoundary, now: now, dueSoonDays: 3))
    }

    func testDueSoonZeroDaysMeansOverdueOnly() {
        // dueSoonDays=0: Fenster [now, now] — nur Tasks fällig exakt jetzt oder früher
        // fallen in overdue, nicht in dueSoon (dueSoon verlangt dueSeconds >= nowSeconds).
        // Ein Task, der 1s in der Zukunft liegt, passt nicht.
        let filter = SidebarFilter.dueSoon
        let almostNow = task(due: Int64(now.timeIntervalSince1970) + 1)
        XCTAssertFalse(filter.matches(almostNow, now: now, dueSoonDays: 0))
    }

    // MARK: - inbox schliesst waiting und upcoming aus

    func testInboxExcludesWaitingTask() {
        // Pending, kein Projekt, keine Tags — aber Wartezeit in der Zukunft → kein Inbox.
        let t = task(wait: ts(1))
        XCTAssertFalse(SidebarFilter.inbox.matches(t, now: now, dueSoonDays: 7))
    }

    func testInboxExcludesUpcomingTask() {
        // Pending, kein Projekt, keine Tags — aber scheduled in der Zukunft → kein Inbox.
        let t = task(scheduled: ts(2))
        XCTAssertFalse(SidebarFilter.inbox.matches(t, now: now, dueSoonDays: 7))
    }

    func testInboxIncludesPastWait() {
        // Wait in der Vergangenheit → Task ist aktiv, gehört in Inbox (sofern kein Projekt/Tag).
        let t = task(wait: ts(-1))
        XCTAssertTrue(SidebarFilter.inbox.matches(t, now: now, dueSoonDays: 7))
    }

    func testInboxIncludesPastScheduled() {
        // Scheduled in der Vergangenheit → kein Upcoming mehr, gehört in Inbox.
        let t = task(scheduled: ts(-1))
        XCTAssertTrue(SidebarFilter.inbox.matches(t, now: now, dueSoonDays: 7))
    }

    // MARK: - recurring-Status-Verhalten

    func testRecurringVisibleInAll() {
        // Recurring-Master-Tasks sollen in .all sichtbar sein.
        let t = task(status: .recurring)
        XCTAssertTrue(SidebarFilter.all.matches(t, now: now, dueSoonDays: 7))
    }

    func testRecurringExcludedFromTodo() {
        // .todo gated auf .pending → recurring fällt raus.
        let t = task(status: .recurring)
        XCTAssertFalse(SidebarFilter.todo.matches(t, now: now, dueSoonDays: 7))
    }

    func testRecurringVisibleInProjectFilter() {
        // Projekt-Filter hat kein Status-Gate — recurring mit dem Projekt ist sichtbar.
        let t = task(project: "Haus", status: .recurring)
        XCTAssertTrue(SidebarFilter.project("Haus").matches(t, now: now, dueSoonDays: 7))
    }
}
