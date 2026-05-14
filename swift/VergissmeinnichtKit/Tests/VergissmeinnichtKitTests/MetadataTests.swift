import XCTest
@testable import VergissmeinnichtKit

/// Tests für die Metadata-Mutationen, die in Welle A und S zur FFI ergänzt wurden:
/// `set_project`, `set_due`, `set_priority`, `set_wait`, `set_recur`,
/// `add_tag`/`remove_tag`, `update_task_metadata`, `add_task_full`, `reactivate`.
final class MetadataTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    func testAddTaskFullPersistsAllFields() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let due: Int64 = 1_800_000_000
        let uuid = try store.addTaskFull(
            description: "vollständiger Task",
            project: "arbeit",
            tags: ["eilig", "wichtig"],
            due: due
        )

        let task = try XCTUnwrap(try store.listPending().first { $0.uuid == uuid })
        XCTAssertEqual(task.project, "arbeit")
        XCTAssertEqual(Set(task.tags), Set(["eilig", "wichtig"]))
        XCTAssertEqual(task.due, due)
    }

    func testSetProjectAddsAndClears() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTask(description: "ohne Projekt")

        try store.setProject(uuid: uuid, project: "neu")
        var task = try XCTUnwrap(try store.listPending().first { $0.uuid == uuid })
        XCTAssertEqual(task.project, "neu")

        try store.setProject(uuid: uuid, project: nil)
        task = try XCTUnwrap(try store.listPending().first { $0.uuid == uuid })
        XCTAssertNil(task.project)
    }

    func testAddRemoveTagsAreIdempotent() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTask(description: "tagging")

        try store.addTag(uuid: uuid, tag: "foo")
        try store.addTag(uuid: uuid, tag: "foo") // idempotent

        var task = try XCTUnwrap(try store.listPending().first { $0.uuid == uuid })
        XCTAssertEqual(task.tags, ["foo"])

        try store.removeTag(uuid: uuid, tag: "foo")
        try store.removeTag(uuid: uuid, tag: "foo") // idempotent
        task = try XCTUnwrap(try store.listPending().first { $0.uuid == uuid })
        XCTAssertTrue(task.tags.isEmpty)
    }

    func testSetDuePriorityWaitRecurRoundtrip() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTask(description: "metadata-roundtrip")
        let due: Int64 = 1_900_000_000
        let wait: Int64 = 1_950_000_000
        let scheduled: Int64 = 1_850_000_000

        try store.setDue(uuid: uuid, due: due)
        try store.setPriority(uuid: uuid, priority: "H")
        try store.setWait(uuid: uuid, wait: wait)
        try store.setRecur(uuid: uuid, recur: "weekly")
        try store.setScheduled(uuid: uuid, scheduled: scheduled)

        let task = try XCTUnwrap(
            try store.listTasks(includeCompleted: true).first { $0.uuid == uuid }
        )
        XCTAssertEqual(task.due, due)
        XCTAssertEqual(task.priority, "H")
        XCTAssertEqual(task.wait, wait)
        XCTAssertEqual(task.recur, "weekly")
        XCTAssertEqual(task.scheduled, scheduled)
    }

    func testMarkDoneWithFollowupCreatesNewInstance() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let originalUuid = try store.addTaskFull(
            description: "wöchentlicher Check",
            project: "routine",
            tags: ["wartung"],
            due: 1_800_000_000
        )
        try store.setRecur(uuid: originalUuid, recur: "weekly")
        try store.setPriority(uuid: originalUuid, priority: "M")

        let newUuid = try store.markDoneWithFollowup(
            uuid: originalUuid,
            newDue: 1_800_604_800, // +1 Woche in Sekunden
            recur: "weekly",
            priority: "M",
            project: "routine",
            tags: ["wartung"],
            description: "wöchentlicher Check"
        )
        XCTAssertNotNil(newUuid)

        let all = try store.listTasks(includeCompleted: true)
        let oldTask = try XCTUnwrap(all.first { $0.uuid == originalUuid })
        XCTAssertEqual(oldTask.status, .completed)

        let newTask = try XCTUnwrap(all.first { $0.uuid == newUuid })
        XCTAssertEqual(newTask.status, .pending)
        XCTAssertEqual(newTask.description, "wöchentlicher Check")
        XCTAssertEqual(newTask.project, "routine")
        XCTAssertEqual(newTask.tags, ["wartung"])
        XCTAssertEqual(newTask.due, 1_800_604_800)
        XCTAssertEqual(newTask.priority, "M")
        XCTAssertEqual(newTask.recur, "weekly")
    }

    func testMarkDoneWithFollowupWithoutRecurDoesNotCreate() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTask(description: "Einmal-Task")

        let newUuid = try store.markDoneWithFollowup(
            uuid: uuid,
            newDue: nil,
            recur: nil,
            priority: nil,
            project: nil,
            tags: [],
            description: "Einmal-Task"
        )
        XCTAssertNil(newUuid)
        XCTAssertTrue(try store.listPending().isEmpty)
    }

    func testUpdateTaskMetadataReplacesTags() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTaskFull(
            description: "alt",
            project: "alt-projekt",
            tags: ["alt-a", "alt-b"],
            due: 1_800_000_000
        )

        try store.updateTaskMetadata(
            uuid: uuid,
            description: "neu",
            project: "neu-projekt",
            tags: ["neu"],
            due: nil
        )

        let task = try XCTUnwrap(try store.listPending().first { $0.uuid == uuid })
        XCTAssertEqual(task.description, "neu")
        XCTAssertEqual(task.project, "neu-projekt")
        XCTAssertEqual(task.tags, ["neu"])
        XCTAssertNil(task.due)
    }

    func testReactivateRestoresPending() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTask(description: "wird erledigt")
        try store.markDone(uuid: uuid)

        XCTAssertTrue(try store.listPending().isEmpty)
        try store.reactivate(uuid: uuid)

        let pending = try store.listPending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.uuid, uuid)
    }

    func testRemoveAnnotationRemovesByEntry() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTask(description: "mit anno")
        try store.addAnnotation(uuid: uuid, annotation: "erste Notiz")

        var task = try XCTUnwrap(try store.listPending().first { $0.uuid == uuid })
        XCTAssertEqual(task.annotations.count, 1)
        let entry = try XCTUnwrap(task.annotations.first?.entry)

        try store.removeAnnotation(uuid: uuid, entry: entry)
        task = try XCTUnwrap(try store.listPending().first { $0.uuid == uuid })
        XCTAssertTrue(task.annotations.isEmpty)
    }
}
