import XCTest
import VergissmeinnichtKit
@testable import Vergissmeinnicht

/// Unit-Tests für `DependencyTree.rows(visible:all:collapsed:)` — die reine
/// Anordnungslogik des Abhängigkeitsbaums (Eltern = Voraussetzung, Kinder = Tasks, die von ihr abhängen).
final class DependencyTreeTests: XCTestCase {

    private func task(_ uuid: String, depends: [String] = [], status: TaskStatus = .pending) -> TaskInfo {
        TaskInfo(
            uuid: uuid, description: "Task \(uuid)", project: nil, tags: [],
            due: nil, status: status, entry: nil, workingSetId: nil,
            priority: nil, annotations: [], wait: nil, recur: nil,
            scheduled: nil, depends: depends, isBlocked: false, isBlocking: false, isActive: false
        )
    }

    private func rows(
        _ visible: [TaskInfo], all: [TaskInfo]? = nil, collapsed: Set<String> = []
    ) -> [DependencyTreeRow] {
        DependencyTree.rows(visible: visible, all: all ?? visible, collapsed: collapsed)
    }

    private func ids(_ rows: [DependencyTreeRow]) -> [String] { rows.map { $0.id } }

    // 1
    func testNoDependenciesKeepsInputOrderAtDepthZero() {
        let r = rows([task("c"), task("a"), task("b")])
        XCTAssertEqual(r.map { $0.taskUuid }, ["c", "a", "b"])
        XCTAssertTrue(r.allSatisfy { $0.depth == 0 && $0.kind == .task && !$0.hasChildren })
    }

    // 2 — Beispiel des Nutzers: 02a und 02b hängen von 01 ab.
    func testPrerequisiteIsRootWithDependentsAsChildren() {
        let all = [task("01"), task("02a", depends: ["01"]), task("02b", depends: ["01"])]
        let r = rows(all)
        XCTAssertEqual(ids(r), ["01", "01/02a", "01/02b"])
        XCTAssertEqual(r.map { $0.kind }, [.task, .task, .task])
        XCTAssertEqual(r.map { $0.depth }, [0, 1, 1])
        XCTAssertEqual(r.map { $0.hasChildren }, [true, false, false])
    }

    func testChildrenFollowInputOrder() {
        let r = rows([task("b", depends: ["a"]), task("a"), task("c", depends: ["a"])])
        XCTAssertEqual(ids(r), ["a", "a/b", "a/c"])
        let r2 = rows([task("c", depends: ["a"]), task("a"), task("b", depends: ["a"])])
        XCTAssertEqual(ids(r2), ["a", "a/c", "a/b"])
    }

    // 3
    func testChainDepthsAndBars() {
        let r = rows([task("a"), task("b", depends: ["a"]), task("c", depends: ["b"])])
        XCTAssertEqual(ids(r), ["a", "a/b", "a/b/c"])
        XCTAssertEqual(r.map { $0.depth }, [0, 1, 2])
        XCTAssertEqual(r.map { $0.bars.count }, [0, 1, 2])
        XCTAssertEqual(r[1].bars, [TreeBar(isStart: true, isEnd: false)])
        XCTAssertEqual(r[2].bars, [TreeBar(isStart: false, isEnd: true), TreeBar(isStart: true, isEnd: true)])
        XCTAssertEqual(r.map { $0.hasChildren }, [true, true, false])
        XCTAssertEqual(r[2].parentUuid, "b")
        XCTAssertNil(r[0].parentUuid)
    }

    func testBarRunsThroughAllDescendantsWithoutGap() {
        let r = rows([task("a"), task("b", depends: ["a"]), task("c", depends: ["b"]), task("d", depends: ["a"])])
        XCTAssertEqual(ids(r), ["a", "a/b", "a/b/c", "a/d"])
        // Ebene-0-Balken (Vorfahr a): beginnt an a/b, läuft durch a/b/c, endet an a/d.
        XCTAssertEqual(r.map { $0.bars.first?.isStart }, [nil, true, false, false])
        XCTAssertEqual(r.map { $0.bars.first?.isEnd }, [nil, false, false, true])
        // Ebene-1-Balken (Vorfahr b): nur a/b/c, Start und Ende zugleich.
        XCTAssertEqual(r[2].bars[1], TreeBar(isStart: true, isEnd: true))
    }

    // 4 — D hängt von B und C ab: voll unter B, Verweis unter C.
    func testDiamondShowsDependentOnceAndThenAsReference() {
        let r = rows([task("b"), task("c"), task("d", depends: ["b", "c"])])
        XCTAssertEqual(ids(r), ["b", "b/d", "c", "c/d"])
        XCTAssertEqual(r.filter { $0.taskUuid == "d" }.map { $0.kind }, [.task, .reference])
        XCTAssertFalse(r[3].hasChildren)
    }

    // 5
    func testCycleTerminatesWithExactlyOneCycleRow() {
        let r = rows([task("x"), task("a", depends: ["x", "b"]), task("b", depends: ["a"])])
        XCTAssertEqual(ids(r), ["x", "x/a", "x/a/b", "x/a/b/a"])
        XCTAssertEqual(r.filter { $0.kind == .cycle }.count, 1)
        XCTAssertEqual(r.last?.parentUuid, "b")
    }

    func testSelfDependencyYieldsCycleRow() {
        let r = rows([task("a", depends: ["a"])])
        XCTAssertEqual(r.map { $0.kind }, [.task, .cycle])
        XCTAssertEqual(r.map { $0.taskUuid }, ["a", "a"])
    }

    // 6
    func testPureCycleWithoutRootStillShowsAllNodes() {
        let r = rows([task("a", depends: ["b"]), task("b", depends: ["a"])])
        XCTAssertEqual(Set(r.filter { $0.kind == .task }.map { $0.taskUuid }), ["a", "b"])
        XCTAssertEqual(r.filter { $0.kind == .cycle }.count, 1)
    }

    // 7
    func testPendingPrerequisiteNotVisibleIsOutsideRootWithChild() {
        let a = task("a", depends: ["x"])
        let r = rows([a], all: [a, task("x")])
        XCTAssertEqual(ids(r), ["x", "x/a"])
        XCTAssertEqual(r.map { $0.kind }, [.outside, .task])
        XCTAssertTrue(r[0].hasChildren)
    }

    // 8
    func testCompletedPrerequisiteNotVisibleIsCompletedRootWithChild() {
        let a = task("a", depends: ["d"])
        let r = rows([a], all: [a, task("d", status: .completed)])
        XCTAssertEqual(ids(r), ["d", "d/a"])
        XCTAssertEqual(r.map { $0.kind }, [.completed, .task])
    }

    func testCompletedPrerequisiteVisibleIsPlainTask() {
        let a = task("a", depends: ["d"])
        let r = rows([a, task("d", status: .completed)])
        XCTAssertEqual(ids(r), ["d", "d/a"])
        XCTAssertEqual(r.map { $0.kind }, [.task, .task])
    }

    func testCompletedWithoutRelationAndNotVisibleDoesNotAppear() {
        let a = task("a")
        let r = rows([a], all: [a, task("d", status: .completed)])
        XCTAssertEqual(r.map { $0.taskUuid }, ["a"])
    }

    // 9
    func testUnknownAndDeletedTargetsAreOmitted() {
        let a = task("a", depends: ["ghost", "gone"])
        let r = rows([a], all: [a, task("gone", status: .deleted)])
        XCTAssertEqual(ids(r), ["a"])
    }

    func testGhostStandsBeforeItsFirstChild() {
        let a = task("a", depends: ["g"])
        let r = rows([task("x"), task("b"), a], all: [task("x"), task("b"), a, task("g")])
        XCTAssertEqual(ids(r), ["x", "b", "g", "g/a"])
    }

    func testGhostSharedByTwoChildrenAppearsOnce() {
        let a = task("a", depends: ["g"])
        let b = task("b", depends: ["g"])
        let r = rows([a, b], all: [a, b, task("g")])
        XCTAssertEqual(ids(r), ["g", "g/a", "g/b"])
        XCTAssertEqual(r.filter { $0.kind == .reference }.count, 0)
    }

    func testVisibleParentWinsOverGhostParentForFullRow() {
        let b = task("b", depends: ["g", "a"])
        let a = task("a")
        let g = task("g")
        // Geist steht vor b (Position 0 − 0,5), b hat aber eine sichtbare Voraussetzung a.
        let r = rows([b, a], all: [b, a, g])
        XCTAssertEqual(ids(r), ["g", "g/b", "a", "a/b"])
        XCTAssertEqual(r.map { $0.kind }, [.outside, .reference, .task, .task])
        let r2 = rows([a, b], all: [a, b, g])
        XCTAssertEqual(ids(r2), ["a", "a/b", "g", "g/b"])
        XCTAssertEqual(r2[3].kind, .reference)
    }

    // 11
    func testCollapsedHidesDescendantsAndCountsThem() {
        let all = [
            task("a"), task("b", depends: ["a"]), task("c", depends: ["b"]),
            task("d", depends: ["a"]), task("z"),
        ]
        let r = rows(all, collapsed: ["a"])
        XCTAssertEqual(ids(r), ["a", "z"])
        XCTAssertEqual(r[0].hiddenCount, 3)
        XCTAssertTrue(r[0].hasChildren)
        XCTAssertEqual(r[1].hiddenCount, 0)

        let inner = rows(all, collapsed: ["a/b"])
        XCTAssertEqual(ids(inner), ["a", "a/b", "a/d", "z"])
        XCTAssertEqual(inner[1].hiddenCount, 1)
    }

    func testBarsAreComputedAfterCollapsing() {
        let all = [task("a"), task("b", depends: ["a"]), task("c", depends: ["b"]), task("d", depends: ["a"])]
        let r = rows(all, collapsed: ["a/b"])
        XCTAssertEqual(ids(r), ["a", "a/b", "a/d"])
        XCTAssertEqual(r[1].bars, [TreeBar(isStart: true, isEnd: false)])
        XCTAssertEqual(r[2].bars, [TreeBar(isStart: false, isEnd: true)])
    }

    func testGhostCanBeCollapsed() {
        let a = task("a", depends: ["g"])
        let b = task("b", depends: ["g"])
        let r = rows([a, b], all: [a, b, task("g")], collapsed: ["g"])
        XCTAssertEqual(ids(r), ["g"])
        XCTAssertEqual(r[0].hiddenCount, 2)
        XCTAssertTrue(r[0].hasChildren)
    }

    func testCollapsingDoesNotChangeFirstOccurrence() {
        let all = [task("b"), task("c"), task("d", depends: ["b", "c"])]
        let r = rows(all, collapsed: ["b"])
        XCTAssertEqual(r.first { $0.id == "c/d" }?.kind, .reference)
    }

    // 12
    func testEveryVisibleTaskAppearsExactlyOnceAsTask() {
        let all = [
            task("a"), task("b", depends: ["a", "g"]), task("c", depends: ["a", "d"]),
            task("d", depends: ["c"]), task("e", depends: ["b", "c"]),
            task("f", depends: ["f"]), task("h", depends: ["ghost"]), task("i"),
        ]
        let g = task("g", status: .completed)
        let r = DependencyTree.rows(visible: all, all: all + [g], collapsed: [])
        let mains = r.filter { $0.kind == .task }.map { $0.taskUuid }
        XCTAssertEqual(mains.count, Set(mains).count)
        XCTAssertEqual(Set(mains), Set(all.map { $0.uuid }))
        XCTAssertEqual(Set(r.map { $0.id }).count, r.count)
    }
}
