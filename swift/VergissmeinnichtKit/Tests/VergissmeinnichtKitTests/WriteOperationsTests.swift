import XCTest
@testable import VergissmeinnichtKit

final class WriteOperationsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try super.tearDownWithError()
    }

    func testMarkDoneRemovesFromPending() throws {
        // Verify-Bedingung: nach mark_done erscheint die Task nicht mehr in list_pending.
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTask(description: "zu erledigen")

        XCTAssertEqual(try store.listPending().count, 1)

        try store.markDone(uuid: uuid)

        let pending = try store.listPending()
        XCTAssertTrue(
            pending.isEmpty,
            "Erwartete leere Pending-Liste nach markDone, bekam \(pending.count) Einträge"
        )
    }

    func testModifyDescriptionUpdatesEntry() throws {
        // Verify-Bedingung: nach modify_description liefert list_pending die neue Description.
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTask(description: "alte Beschreibung")

        let neueBeschreibung = "neue Beschreibung mit Umlauten äöüß"
        try store.modifyDescription(uuid: uuid, newDescription: neueBeschreibung)

        let pending = try store.listPending()
        XCTAssertEqual(pending.count, 1)
        let entry = try XCTUnwrap(pending.first)
        XCTAssertEqual(entry.uuid, uuid)
        XCTAssertEqual(entry.description, neueBeschreibung)
    }

    func testDeleteTaskRemovesFromPending() throws {
        // Verify-Bedingung: nach delete_task erscheint die Task nicht mehr in list_pending.
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTask(description: "zu löschen")

        XCTAssertEqual(try store.listPending().count, 1)

        try store.deleteTask(uuid: uuid)

        let pending = try store.listPending()
        XCTAssertTrue(
            pending.isEmpty,
            "Erwartete leere Pending-Liste nach deleteTask, bekam \(pending.count) Einträge"
        )
    }

    func testAddAnnotationDoesNotChangePending() throws {
        // Verify-Bedingung: add_annotation throwt nicht und ändert die Description nicht.
        // Annotation-Read-API existiert noch nicht — Verifikation des Inhalts kommt später.
        let store = try TaskStore(dbPath: tempDir.path)
        let beschreibung = "Task mit Annotation"
        let uuid = try store.addTask(description: beschreibung)

        XCTAssertNoThrow(
            try store.addAnnotation(uuid: uuid, annotation: "erste Notiz zur Task")
        )

        let pending = try store.listPending()
        XCTAssertEqual(pending.count, 1)
        let entry = try XCTUnwrap(pending.first)
        XCTAssertEqual(entry.uuid, uuid)
        XCTAssertEqual(
            entry.description,
            beschreibung,
            "Annotation darf die Description der Task nicht ändern"
        )
    }
}
