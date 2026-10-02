import XCTest
import VergissmeinnichtKit
@testable import Vergissmeinnicht

/// Unit-Tests für `DependencyGraph.wouldCreateCycle` und `DependencyCandidates.filter`.
final class DependencyGraphTests: XCTestCase {

    private func task(
        _ uuid: String, depends: [String] = [], status: TaskStatus = .pending,
        id: UInt32? = nil, description: String? = nil, project: String? = nil
    ) -> TaskInfo {
        TaskInfo(
            uuid: uuid, description: description ?? "Task \(uuid)", project: project, tags: [],
            due: nil, status: status, entry: nil, workingSetId: id,
            priority: nil, annotations: [], wait: nil, recur: nil,
            scheduled: nil, depends: depends, isBlocked: false, isBlocking: false, isActive: false
        )
    }

    // MARK: - wouldCreateCycle

    func testSelfReferenceIsCycle() {
        XCTAssertTrue(DependencyGraph.wouldCreateCycle(task: "a", dependsOn: "a", tasks: [task("a")]))
    }

    func testDirectAndTransitiveCycle() {
        let tasks = [task("a"), task("b", depends: ["a"]), task("c", depends: ["b"])]
        // a von b abhängig machen: b hängt schon von a ab → Zyklus.
        XCTAssertTrue(DependencyGraph.wouldCreateCycle(task: "a", dependsOn: "b", tasks: tasks))
        // a von c abhängig machen: c → b → a → Zyklus.
        XCTAssertTrue(DependencyGraph.wouldCreateCycle(task: "a", dependsOn: "c", tasks: tasks))
    }

    func testNoCycleForIndependentOrForwardEdge() {
        let tasks = [task("a"), task("b", depends: ["a"]), task("c")]
        XCTAssertFalse(DependencyGraph.wouldCreateCycle(task: "c", dependsOn: "a", tasks: tasks))
        XCTAssertFalse(DependencyGraph.wouldCreateCycle(task: "c", dependsOn: "b", tasks: tasks))
    }

    func testCompletedTasksCountAsEdges() {
        let tasks = [task("a"), task("b", depends: ["a"], status: .completed)]
        XCTAssertTrue(DependencyGraph.wouldCreateCycle(task: "a", dependsOn: "b", tasks: tasks))
    }

    func testTerminatesOnForeignCycleAndUnknownUuids() {
        let tasks = [task("x", depends: ["y", "ghost"]), task("y", depends: ["x"]), task("t")]
        XCTAssertFalse(DependencyGraph.wouldCreateCycle(task: "t", dependsOn: "x", tasks: tasks))
        XCTAssertFalse(DependencyGraph.wouldCreateCycle(task: "t", dependsOn: "unknown", tasks: tasks))
    }

    // MARK: - DependencyCandidates.filter

    func testEmptyQueryReturnsFirstTwelveInListOrder() {
        let me = task("me")
        let others = (0..<20).map { task("t\($0)") }
        let r = DependencyCandidates.filter(query: "", task: me, tasks: [me] + others)
        XCTAssertEqual(r.map { $0.uuid }, (0..<12).map { "t\($0)" })
    }

    func testIdQueryMatchesExactlyWithAndWithoutHash() {
        let me = task("me")
        let tasks = [me, task("a", id: 12), task("b", id: 120), task("c", id: 1)]
        XCTAssertEqual(DependencyCandidates.filter(query: "#12", task: me, tasks: tasks).map { $0.uuid }, ["a"])
        XCTAssertEqual(DependencyCandidates.filter(query: "12", task: me, tasks: tasks).map { $0.uuid }, ["a"])
    }

    func testSubstringInTitleOrProjectCaseInsensitive() {
        let me = task("me")
        let tasks = [
            me, task("a", description: "Steuer machen"), task("b", description: "Einkauf", project: "Haushalt.STEUER"),
            task("c", description: "Sport"),
        ]
        XCTAssertEqual(DependencyCandidates.filter(query: "steu", task: me, tasks: tasks).map { $0.uuid }, ["a", "b"])
    }

    func testExcludesSelfLinkedNonPendingAndCycleCandidates() {
        let me = task("me", depends: ["linked"])
        let tasks = [
            me, task("linked"), task("done", status: .completed), task("ok"),
            task("cyc", depends: ["me"]),
        ]
        XCTAssertEqual(DependencyCandidates.filter(query: "", task: me, tasks: tasks).map { $0.uuid }, ["ok"])
    }

    func testLimitIsApplied() {
        let me = task("me")
        let tasks = [me] + (0..<30).map { task("t\($0)", description: "Treffer \($0)") }
        XCTAssertEqual(DependencyCandidates.filter(query: "Treffer", task: me, tasks: tasks).count, 12)
    }
}
