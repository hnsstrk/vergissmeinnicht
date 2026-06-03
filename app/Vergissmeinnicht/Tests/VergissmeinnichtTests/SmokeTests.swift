import XCTest
@testable import Vergissmeinnicht

/// Minimaler Rauchtest: beweist, dass das App-Test-Target gegen den Host-App-Modul
/// linkt (`@testable import Vergissmeinnicht`) und Kit-Symbole sichtbar sind.
final class SmokeTests: XCTestCase {
    func testTestTargetLinksAgainstApp() {
        // Greift auf einen App-internen, pure Typ zu — verifiziert nur, dass der
        // @testable-Import auflöst.
        let preview = QuickCaptureParser.parse("hallo welt")
        XCTAssertEqual(preview.description, "hallo welt")
    }
}
