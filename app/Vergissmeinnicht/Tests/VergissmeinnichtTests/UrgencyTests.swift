import XCTest
import VergissmeinnichtKit
@testable import Vergissmeinnicht

/// Unit-Tests für `Urgency.score` (Taskwarrior-Standardkoeffizienten) und die
/// Sortierung nach Dringlichkeit im `TaskListViewModel`.
@MainActor
final class UrgencyTests: XCTestCase {

    /// Fester Bezugszeitpunkt: 2026-07-01T10:00:00Z.
    private let now = Date(timeIntervalSince1970: 1_751_364_000)
    private let day: Double = 86_400

    private func ts(_ days: Double) -> Int64 {
        Int64(now.timeIntervalSince1970 + days * day)
    }

    /// `entry` ist standardmäßig `now`, damit der Alters-Term 0 ist.
    private func task(
        uuid: String = UUID().uuidString,
        description: String = "Task",
        project: String? = nil,
        tags: [String] = [],
        due: Int64? = nil,
        entry: Int64? = Int64(1_751_364_000),
        priority: String? = nil,
        annotations: Int = 0,
        wait: Int64? = nil,
        scheduled: Int64? = nil,
        isBlocked: Bool = false,
        isBlocking: Bool = false,
        isActive: Bool = false
    ) -> TaskInfo {
        TaskInfo(
            uuid: uuid, description: description, project: project, tags: tags,
            due: due, status: .pending, entry: entry, workingSetId: nil,
            priority: priority,
            annotations: (0..<annotations).map { AnnotationInfo(entry: Int64($0), description: "a\($0)") },
            wait: wait, recur: nil, scheduled: scheduled, depends: [],
            isBlocked: isBlocked, isBlocking: isBlocking, isActive: isActive
        )
    }

    private func score(_ t: TaskInfo) -> Double { Urgency.score(t, now: now) }

    private func assertScore(_ t: TaskInfo, _ expected: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(score(t), expected, accuracy: 0.001, file: file, line: line)
    }

    func testEmptyTaskScoresZero() { assertScore(task(), 0.0) }

    func testPriority() {
        assertScore(task(priority: "H"), 6.0)
        assertScore(task(priority: "M"), 3.9)
        assertScore(task(priority: "L"), 1.8)
        assertScore(task(priority: "X"), 0.0)
    }

    func testNextTag() { assertScore(task(tags: ["next"]), 15.8) }

    func testDueNow() { assertScore(task(due: ts(0)), 8.8) }

    func testDueOverdueSevenDaysOrMoreIsFull() {
        assertScore(task(due: ts(-7)), 12.0)
        assertScore(task(due: ts(-30)), 12.0)
    }

    func testDueInFuture() {
        assertScore(task(due: ts(7)), 5.6)
        assertScore(task(due: ts(14)), 2.4)
        assertScore(task(due: ts(30)), 2.4)
    }

    func testAge() {
        assertScore(task(entry: ts(-73)), 0.4)
        assertScore(task(entry: ts(-365)), 2.0)
        assertScore(task(entry: ts(-400)), 2.0)
        assertScore(task(entry: nil), 2.0)
    }

    func testAgeTruncatesToWholeDays() {
        assertScore(task(entry: ts(-1.5)), 2.0 / 365.0)
    }

    func testAnnotations() {
        assertScore(task(annotations: 1), 0.8)
        assertScore(task(annotations: 2), 0.9)
        assertScore(task(annotations: 3), 1.0)
    }

    func testTagCount() {
        assertScore(task(tags: ["a", "b"]), 0.9)
        assertScore(task(tags: ["a", "b", "c", "d"]), 1.0)
    }

    func testProject() { assertScore(task(project: "Work"), 1.0) }

    func testBlockedAndBlocking() {
        assertScore(task(isBlocked: true), -5.0)
        assertScore(task(isBlocking: true), 8.0)
        assertScore(task(isBlocked: true, isBlocking: true), 3.0)
    }

    func testWaiting() {
        assertScore(task(wait: ts(1)), -3.0)
        assertScore(task(wait: ts(-1)), 0.0)
    }

    func testScheduled() {
        assertScore(task(scheduled: ts(-1)), 5.0)
        assertScore(task(scheduled: ts(1)), 0.0)
    }

    func testActive() { assertScore(task(isActive: true), 4.0) }

    func testCombined() {
        let t = task(project: "Work", tags: ["next", "home"], due: ts(0), entry: ts(-73), priority: "M")
        assertScore(t, 30.0)
    }

    func testViewModelSortsByUrgencyHighestFirstWithNameTieBreak() {
        let vm = TaskListViewModel()
        vm.activeFilter = .all
        vm.sortOrder = .urgency
        vm.sortAscending = true
        let pool = [
            task(uuid: "low", description: "Zebra", priority: "L"),
            task(uuid: "high", description: "Mittel", priority: "H"),
            task(uuid: "tieB", description: "Beta", priority: "M"),
            task(uuid: "tieA", description: "Alpha", priority: "M"),
        ]
        XCTAssertEqual(vm.visibleTasks(from: pool, now: now).map { $0.uuid }, ["high", "tieA", "tieB", "low"])
        vm.sortAscending = false
        XCTAssertEqual(vm.visibleTasks(from: pool, now: now).map { $0.uuid }, ["low", "tieB", "tieA", "high"])
    }
}
