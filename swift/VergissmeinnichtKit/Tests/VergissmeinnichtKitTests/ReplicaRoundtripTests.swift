import XCTest
@testable import VergissmeinnichtKit

final class ReplicaRoundtripTests: XCTestCase {
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

    func testOpenReplicaInTempDirSucceeds() throws {
        // Verify-Bedingung: TaskStore lässt sich auf einem leeren temp-Verzeichnis öffnen.
        XCTAssertNoThrow(try TaskStore(dbPath: tempDir.path))
    }

    func testAddTaskReturnsValidUuid() throws {
        // Verify-Bedingung: add_task liefert eine UUID in 8-4-4-4-12-Form zurück.
        let store = try TaskStore(dbPath: tempDir.path)
        let uuid = try store.addTask(description: "Erste Aufgabe")

        let pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(uuid.startIndex..., in: uuid)
        XCTAssertNotNil(
            regex.firstMatch(in: uuid, range: range),
            "Erwartete UUID-Form 8-4-4-4-12, bekam \(uuid)"
        )
    }

    func testListPendingReflectsAddedTask() throws {
        // Verify-Bedingung: nach add_task enthält list_pending genau einen Eintrag
        // mit gleicher UUID und Description.
        let store = try TaskStore(dbPath: tempDir.path)
        let description = "Roundtrip-Aufgabe äöüß"
        let uuid = try store.addTask(description: description)

        let pending = try store.listPending()
        XCTAssertEqual(pending.count, 1, "Erwartete genau eine Pending-Task, bekam \(pending.count)")
        let entry = try XCTUnwrap(pending.first)
        XCTAssertEqual(entry.uuid, uuid)
        XCTAssertEqual(entry.description, description)
    }
}
