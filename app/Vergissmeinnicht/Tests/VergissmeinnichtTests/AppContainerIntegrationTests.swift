import XCTest
import VergissmeinnichtKit
@testable import Vergissmeinnicht

/// Integrationstests der drei Kern-Mutationen des `AppContainer` (#8) gegen eine
/// echte, isolierte Replica im Temp-Verzeichnis. Möglich gemacht durch den
/// test-only `init(replicaURL:)` (siehe AppContainer.swift) — der einzige
/// Produktiv-Code-Touch dieses Bundles; bewusst `internal`, von `@testable`
/// erreichbar, keine API-Verbreiterung.
///
/// AppContainer ist `@MainActor`; die Tests sind entsprechend `@MainActor` und async.
/// `await`-Aufrufe werden in lokale Variablen aufgelöst, bevor sie assertiert werden —
/// die XCTest-Autoclosures unterstützen kein `async`.
@MainActor
final class AppContainerIntegrationTests: XCTestCase {

    private var tempDir: URL!

    // Die async-Varianten von setUp/tearDown erben in einer `@MainActor`-Klasse
    // deren Isolation — anders als die synchronen `*WithError`-Overrides nonisolated
    // XCTest-Methoden, in denen Swift 6.0 die Mutation des main-actor-isolierten
    // `tempDir` ablehnt (CI ist mit Swift 6.0 strenger als das lokale 6.3).
    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        try await super.tearDown()
    }

    private func makeContainer() throws -> AppContainer {
        try AppContainer(replicaURL: tempDir)
    }

    /// Gregorianischer UTC-Kalender — deterministisch für Intervall-Tests
    /// (keine DST-Sprünge in UTC).
    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // MARK: - markDoneWithRecurrence

    func testMarkDoneWeeklyCreatesFollowupPlus7Days() async throws {
        let container = try makeContainer()
        let oldDue: Int64 = 1_700_000_000 // fester Bezugspunkt
        let created = await container.addTask(description: "Müll rausbringen", project: nil, tags: [], due: oldDue)
        let uuid = try XCTUnwrap(created)
        let recurSet = await container.setRecur(uuid: uuid, recur: "weekly")
        XCTAssertTrue(recurSet)

        let ok = await container.markDoneWithRecurrence(uuid: uuid, calendar: utcCalendar())
        XCTAssertTrue(ok)

        // Original erledigt, eine neue Pending-Instanz mit due + 7 Tagen.
        let completed = container.tasks.filter { $0.status == .completed }
        XCTAssertEqual(completed.count, 1)
        let followups = container.tasks.filter { $0.status == .pending }
        XCTAssertEqual(followups.count, 1)
        let followup = try XCTUnwrap(followups.first)
        XCTAssertEqual(followup.due, oldDue + 7 * 86_400)
        XCTAssertEqual(followup.description, "Müll rausbringen")
        XCTAssertEqual(followup.recur, "weekly")
    }

    func testMarkDoneWithoutRecurNoFollowup() async throws {
        let container = try makeContainer()
        let created = await container.addTask(description: "Einmalig", project: nil, tags: [], due: 1_700_000_000)
        let uuid = try XCTUnwrap(created)
        // Kein recur → keine Folge-Instanz.
        let ok = await container.markDoneWithRecurrence(uuid: uuid, calendar: utcCalendar())
        XCTAssertTrue(ok)
        XCTAssertEqual(container.tasks.filter { $0.status == .pending }.count, 0)
        XCTAssertEqual(container.tasks.filter { $0.status == .completed }.count, 1)
    }

    func testMarkDoneRecurWithoutDueNoFollowup() async throws {
        let container = try makeContainer()
        let created = await container.addTask(description: "Ohne Fälligkeit")
        let uuid = try XCTUnwrap(created)
        let recurSet = await container.setRecur(uuid: uuid, recur: "daily")
        XCTAssertTrue(recurSet)
        // recur gesetzt, aber kein due → kein Folge-Task (Rust-Gate verlangt beides).
        let ok = await container.markDoneWithRecurrence(uuid: uuid, calendar: utcCalendar())
        XCTAssertTrue(ok)
        XCTAssertEqual(container.tasks.filter { $0.status == .pending }.count, 0)
    }

    func testMarkDoneMonthlyCrossesMonthBoundary() async throws {
        let container = try makeContainer()
        let cal = utcCalendar()
        // 31.01.2026 12:00 UTC + monthly → 28.02.2026 (Kalender klemmt auf gültigen Tag).
        let jan31 = cal.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12))!
        let oldDue = Int64(jan31.timeIntervalSince1970)
        let created = await container.addTask(description: "Monatsabschluss", project: nil, tags: [], due: oldDue)
        let uuid = try XCTUnwrap(created)
        let recurSet = await container.setRecur(uuid: uuid, recur: "monthly")
        XCTAssertTrue(recurSet)

        let ok = await container.markDoneWithRecurrence(uuid: uuid, calendar: cal)
        XCTAssertTrue(ok)
        let followup = try XCTUnwrap(container.tasks.first { $0.status == .pending })
        let expected = cal.date(byAdding: DateComponents(month: 1), to: jan31)!
        XCTAssertEqual(followup.due, Int64(expected.timeIntervalSince1970))
        // Februar 2026 hat 28 Tage → Folge-Due liegt am 28.02.
        let comps = cal.dateComponents([.month, .day], from: expected)
        XCTAssertEqual(comps.month, 2)
        XCTAssertEqual(comps.day, 28)
    }

    func testMarkDoneAcrossDSTUsesCalendarArithmetic() async throws {
        // Berlin-Zeitzone: DST-Umstellung Ende März 2026 (29.03.). Ein weekly-Intervall
        // über die Grenze ist via Calendar-Arithmetik exakt +1 Woche kalendarisch —
        // wir verifizieren, dass derselbe Kalender genutzt wird, statt 7*86400 stumpf
        // zu addieren (was bei DST um eine Stunde danebenläge).
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let container = try makeContainer()
        let mar26 = berlin.date(from: DateComponents(year: 2026, month: 3, day: 26, hour: 9))!
        let oldDue = Int64(mar26.timeIntervalSince1970)
        let created = await container.addTask(description: "DST-Test", project: nil, tags: [], due: oldDue)
        let uuid = try XCTUnwrap(created)
        let recurSet = await container.setRecur(uuid: uuid, recur: "weekly")
        XCTAssertTrue(recurSet)

        let ok = await container.markDoneWithRecurrence(uuid: uuid, calendar: berlin)
        XCTAssertTrue(ok)
        let followup = try XCTUnwrap(container.tasks.first { $0.status == .pending })
        let expected = berlin.date(byAdding: DateComponents(weekOfYear: 1), to: mar26)!
        XCTAssertEqual(followup.due, Int64(expected.timeIntervalSince1970))
    }

    // MARK: - renameProject

    func testRenameProjectMovesAllMatchingTasks() async throws {
        let container = try makeContainer()
        _ = await container.addTask(description: "A", project: "Alt", tags: [], due: nil)
        _ = await container.addTask(description: "B", project: "Alt", tags: [], due: nil)
        _ = await container.addTask(description: "C", project: "Andere", tags: [], due: nil)

        let count = await container.renameProject(from: "Alt", to: "Neu")
        XCTAssertEqual(count, 2)
        XCTAssertEqual(container.tasks.filter { $0.project == "Neu" }.count, 2)
        XCTAssertEqual(container.tasks.filter { $0.project == "Alt" }.count, 0)
        XCTAssertEqual(container.tasks.filter { $0.project == "Andere" }.count, 1)
        XCTAssertNil(container.lastError)
    }

    func testRenameProjectIdempotentOnNoMatch() async throws {
        let container = try makeContainer()
        _ = await container.addTask(description: "A", project: "X", tags: [], due: nil)
        // Kein Task mit "Nichtvorhanden" → 0 Umbenennungen, kein Fehler.
        let count = await container.renameProject(from: "Nichtvorhanden", to: "Y")
        XCTAssertEqual(count, 0)
        XCTAssertNil(container.lastError)
        // Doppelter Rename auf dasselbe Ziel ist idempotent (zweiter Lauf findet nichts).
        let first = await container.renameProject(from: "X", to: "Z")
        XCTAssertEqual(first, 1)
        let second = await container.renameProject(from: "X", to: "Z")
        XCTAssertEqual(second, 0)
        XCTAssertEqual(container.tasks.filter { $0.project == "Z" }.count, 1)
    }

    func testClearProjectRemovesAssignment() async throws {
        let container = try makeContainer()
        _ = await container.addTask(description: "A", project: "Weg", tags: [], due: nil)
        let count = await container.clearProject(name: "Weg")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(container.tasks.filter { $0.project == nil }.count, 1)
    }

    // MARK: - repairLegacyTasks

    func testRepairConvertsLegacyDescriptionToProperties() async throws {
        let container = try makeContainer()
        // Legacy-Task: Metadaten stecken noch als Text in der Description, Properties leer.
        _ = await container.addTask(description: "Einkaufen +haushalt project:Privat")
        let repaired = await container.repairLegacyTasks()
        XCTAssertEqual(repaired, 1)

        let task = try XCTUnwrap(container.tasks.first { $0.status == .pending })
        XCTAssertEqual(task.description, "Einkaufen")
        XCTAssertEqual(task.project, "Privat")
        XCTAssertEqual(task.tags, ["haushalt"])
    }

    func testRepairIsIdempotent() async throws {
        let container = try makeContainer()
        _ = await container.addTask(description: "Aufräumen +zuhause project:Haus")
        let firstRun = await container.repairLegacyTasks()
        XCTAssertEqual(firstRun, 1)
        // Zweiter Lauf: Task hat jetzt Properties → nichts mehr zu reparieren.
        let secondRun = await container.repairLegacyTasks()
        XCTAssertEqual(secondRun, 0)
    }

    func testRepairSkipsTasksThatAlreadyHaveProperties() async throws {
        let container = try makeContainer()
        // Task hat bereits ein Projekt → trotz "+tag"-Prosa NICHT anfassen (Karpathy 3).
        _ = await container.addTask(description: "Notiz mit +stichwort im Text", project: "Bestand", tags: [], due: nil)
        let repaired = await container.repairLegacyTasks()
        XCTAssertEqual(repaired, 0)
        let task = try XCTUnwrap(container.tasks.first)
        XCTAssertEqual(task.description, "Notiz mit +stichwort im Text")
        XCTAssertEqual(task.project, "Bestand")
    }

    func testRepairSkipsPlainTasks() async throws {
        let container = try makeContainer()
        _ = await container.addTask(description: "Ganz normaler Task ohne Metadaten")
        let repaired = await container.repairLegacyTasks()
        XCTAssertEqual(repaired, 0)
    }

    // MARK: - #5 Batch (Smoke: erfolgreiche Mehrfach-Operation)

    func testMarkDoneBatchCompletesAllSelected() async throws {
        let container = try makeContainer()
        let c1 = await container.addTask(description: "Eins")
        let c2 = await container.addTask(description: "Zwei")
        let u1 = try XCTUnwrap(c1)
        let u2 = try XCTUnwrap(c2)
        await container.markDoneBatch(uuids: [u1, u2])
        XCTAssertEqual(container.tasks.filter { $0.status == .pending }.count, 0)
        XCTAssertEqual(container.tasks.filter { $0.status == .completed }.count, 2)
        // Alle erfolgreich → kein Teilfehler-Banner.
        XCTAssertNil(container.lastError)
    }
}
