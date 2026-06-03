import XCTest
@testable import VergissmeinnichtKit

/// FFI-Tests für die nativen Taskwarrior-Abhängigkeiten (`depends`) und die daraus
/// abgeleiteten Reports blocked/blocking/unblocked (Issue #3). Temp-Replica-Muster
/// wie WriteOperationsTests. Alle Tests teilen sich **denselben Store** über eine
/// Mutation hinweg — sonst würde der gecachte `dependency_map` nicht beobachtbar.
final class DependencyTests: XCTestCase {
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

    private func task(_ tasks: [TaskInfo], _ uuid: String) throws -> TaskInfo {
        try XCTUnwrap(tasks.first(where: { $0.uuid == uuid }))
    }

    /// add_dependency setzt `depends`; remove_dependency räumt es ab. Beide idempotent.
    func testAddRemoveDependencyIsIdempotent() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let a = try store.addTask(description: "A")
        let b = try store.addTask(description: "B")

        try store.addDependency(uuid: a, dependsOnUuid: b)
        // Zweiter Aufruf darf nicht fehlschlagen oder duplizieren (idempotent).
        try store.addDependency(uuid: a, dependsOnUuid: b)

        var all = try store.listTasks(includeCompleted: false)
        XCTAssertEqual(try task(all, a).depends, [b], "A soll genau einmal von B abhängen")
        XCTAssertEqual(try task(all, b).depends, [], "B hängt von nichts ab")

        try store.removeDependency(uuid: a, dependsOnUuid: b)
        try store.removeDependency(uuid: a, dependsOnUuid: b) // idempotent

        all = try store.listTasks(includeCompleted: false)
        XCTAssertTrue(try task(all, a).depends.isEmpty, "Abhängigkeit soll entfernt sein")
    }

    /// Kern-Validierung am kleinen Graphen: A hängt von B ab.
    /// B pending → A BLOCKED, B BLOCKING. B erledigt → A UNBLOCKED, B nicht mehr BLOCKING.
    /// Nutzt denselben Store über die Mutation hinweg, damit die depmap-Invalidierung greift.
    func testBlockedBlockingDerivationAcrossCompletion() throws {
        let store = try TaskStore(dbPath: tempDir.path)
        let a = try store.addTask(description: "A")
        let b = try store.addTask(description: "B")
        try store.addDependency(uuid: a, dependsOnUuid: b)

        // B noch pending.
        var all = try store.listTasks(includeCompleted: false)
        XCTAssertTrue(try task(all, a).isBlocked, "A hängt von pending B ab → BLOCKED")
        XCTAssertFalse(try task(all, a).isBlocking, "A blockiert niemanden")
        XCTAssertFalse(try task(all, b).isBlocked, "B hängt von nichts ab")
        XCTAssertTrue(try task(all, b).isBlocking, "B blockiert A → BLOCKING")

        // B erledigen — depmap wird durch commit_operations invalidiert.
        try store.markDone(uuid: b)

        all = try store.listTasks(includeCompleted: true)
        XCTAssertFalse(try task(all, a).isBlocked, "B erledigt → A nicht mehr BLOCKED (UNBLOCKED)")
        XCTAssertFalse(try task(all, b).isBlocking, "Erledigtes B blockiert nicht mehr")
        // depends bleibt bestehen (alle Stati), nur die Pending-Ableitung ändert sich.
        XCTAssertEqual(try task(all, a).depends, [b], "depends-Property bleibt erhalten")
    }
}
