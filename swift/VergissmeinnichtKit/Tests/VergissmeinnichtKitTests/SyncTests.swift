import XCTest
@testable import VergissmeinnichtKit

final class SyncTests: XCTestCase {
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

    func testSyncWithInvalidCredentialsThrowsCleanly() throws {
        // Verify-Bedingung: sync gegen einen nicht-erreichbaren Server wirft einen
        // sauberen VmError (kein Panic, kein Crash). Der Aufruf darf weder die App
        // killen noch eine andere Exception-Klasse als VmError werfen.
        let store = try TaskStore(dbPath: tempDir.path)

        // Verwende eine garantiert unerreichbare URL und einen Dummy-Client-ID-UUID.
        // Der Server existiert nicht — der Aufruf MUSS scheitern, aber kontrolliert.
        let unreachableUrl = "http://127.0.0.1:1/nonexistent-sync-server"
        let dummyClientId = "00000000-0000-0000-0000-000000000001"
        let dummySecret = "dummy-encryption-secret"

        XCTAssertThrowsError(
            try store.sync(
                serverUrl: unreachableUrl,
                clientId: dummyClientId,
                encryptionSecret: dummySecret
            )
        ) { error in
            XCTAssertTrue(
                error is VmError,
                "Erwartet wurde VmError, bekam \(type(of: error))"
            )
        }
    }
}
