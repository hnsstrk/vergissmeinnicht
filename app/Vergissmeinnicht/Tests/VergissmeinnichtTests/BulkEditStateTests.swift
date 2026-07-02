import XCTest
import VergissmeinnichtKit
@testable import Vergissmeinnicht

/// Tests für die reine Common-Value-Ableitung des Bulk-Editors der Mehrfachauswahl
/// (#33). `BulkEditState`/`BulkFieldValue` sind reine Datentypen ohne FFI-Zugriff.
final class BulkEditStateTests: XCTestCase {

    private func task(
        uuid: String = UUID().uuidString,
        project: String? = nil,
        tags: [String] = [],
        due: Int64? = nil,
        priority: String? = nil,
        scheduled: Int64? = nil
    ) -> TaskInfo {
        TaskInfo(
            uuid: uuid, description: "Task", project: project, tags: tags,
            due: due, status: .pending, entry: nil, workingSetId: nil,
            priority: priority, annotations: [], wait: nil, recur: nil,
            scheduled: scheduled, depends: [], isBlocked: false, isBlocking: false
        )
    }

    // MARK: - uniform / mixed

    func testUniformValueDerivedWhenAllTasksMatch() {
        let tasks = [task(project: "arbeit"), task(project: "arbeit")]
        let state = BulkEditState(tasks: tasks)
        XCTAssertEqual(state.project, .uniform("arbeit"))
    }

    func testUniformNilDerivedWhenNoTaskHasValue() {
        let tasks = [task(project: nil), task(project: nil)]
        let state = BulkEditState(tasks: tasks)
        XCTAssertEqual(state.project, .uniform(nil))
    }

    func testMixedDerivedWhenValuesDiffer() {
        let tasks = [task(project: "arbeit"), task(project: "privat")]
        let state = BulkEditState(tasks: tasks)
        XCTAssertEqual(state.project, .mixed)
    }

    func testMixedDerivedWhenOneHasValueAndOneDoesNot() {
        let tasks = [task(project: "arbeit"), task(project: nil)]
        let state = BulkEditState(tasks: tasks)
        XCTAssertEqual(state.project, .mixed)
    }

    // MARK: - Tag-Menge unabhängig von Reihenfolge

    func testTagSetUniformIgnoresOrder() {
        let tasks = [task(tags: ["eilig", "arbeit"]), task(tags: ["arbeit", "eilig"])]
        let state = BulkEditState(tasks: tasks)
        XCTAssertEqual(state.tagSet, .uniform(Set(["arbeit", "eilig"])))
    }

    func testTagSetMixedWhenTagSetsDiffer() {
        let tasks = [task(tags: ["arbeit"]), task(tags: ["privat"])]
        let state = BulkEditState(tasks: tasks)
        XCTAssertEqual(state.tagSet, .mixed)
    }

    func testTagSetUniformEmptyWhenNoTaskHasTags() {
        let tasks = [task(tags: []), task(tags: [])]
        let state = BulkEditState(tasks: tasks)
        XCTAssertEqual(state.tagSet, .uniform(Set()))
    }

    // MARK: - due / scheduled / priority

    func testDueUniformAndMixed() {
        let uniform = BulkEditState(tasks: [task(due: 100), task(due: 100)])
        XCTAssertEqual(uniform.due, .uniform(100))

        let mixed = BulkEditState(tasks: [task(due: 100), task(due: 200)])
        XCTAssertEqual(mixed.due, .mixed)
    }

    func testScheduledUniformAndMixed() {
        let uniform = BulkEditState(tasks: [task(scheduled: 100), task(scheduled: 100)])
        XCTAssertEqual(uniform.scheduled, .uniform(100))

        let mixed = BulkEditState(tasks: [task(scheduled: 100), task(scheduled: nil)])
        XCTAssertEqual(mixed.scheduled, .mixed)
    }

    func testPriorityUniformAndMixed() {
        let uniform = BulkEditState(tasks: [task(priority: "H"), task(priority: "H")])
        XCTAssertEqual(uniform.priority, .uniform("H"))

        let mixed = BulkEditState(tasks: [task(priority: "H"), task(priority: "L")])
        XCTAssertEqual(mixed.priority, .mixed)
    }

    // MARK: - Einzelelement-Grenzfall

    func testSingleTaskIsAlwaysUniform() {
        let state = BulkEditState(tasks: [task(project: "arbeit", tags: ["eilig"], due: 100, priority: "M", scheduled: 200)])
        XCTAssertEqual(state.project, .uniform("arbeit"))
        XCTAssertEqual(state.tagSet, .uniform(Set(["eilig"])))
        XCTAssertEqual(state.due, .uniform(100))
        XCTAssertEqual(state.priority, .uniform("M"))
        XCTAssertEqual(state.scheduled, .uniform(200))
    }

    // MARK: - BulkFieldValue.derive direkt (Grenzfall: leeres Array)

    func testDeriveOnEmptyArrayYieldsUniformNil() {
        let value: BulkFieldValue<String> = .derive([])
        XCTAssertEqual(value, .uniform(nil))
    }
}
