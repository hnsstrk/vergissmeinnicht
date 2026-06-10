import SwiftUI

struct SettingsView: View {
    @Environment(AppContainer.self) private var container

    @State private var serverUrl        = ""
    @State private var clientId         = ""
    @State private var encryptionSecret = ""
    @State private var statusMessage: String?
    @State private var showRestorePicker: Bool = false

    @AppStorage(AppSettingsKey.language)           private var language: String = AppLanguage.system.rawValue
    @AppStorage(AppSettingsKey.dueSoonDays)        private var dueSoonDays: Int = 7
    @AppStorage(AppSettingsKey.defaultFilter)      private var defaultFilter: String = DefaultFilter.inbox.rawValue
    @AppStorage(AppSettingsKey.defaultSort)        private var defaultSort: String = SortOrder.id.rawValue
    @AppStorage(AppSettingsKey.notifications)      private var notificationsEnabled: Bool = false
    @AppStorage(AppSettingsKey.autoSyncMode)       private var autoSyncMode: String = AutoSyncMode.manual.rawValue
    @AppStorage(AppSettingsKey.sidebarColoredIcons) private var sidebarColoredIcons: Bool = true
    @AppStorage(AppSettingsKey.sidebarProjectHierarchy) private var sidebarProjectHierarchy: Bool = true
    @AppStorage(AppSettingsKey.forecastConfigs) private var forecastConfigsRaw: String = "{}"

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            forecastTab
                .tabItem { Label("Vorschau", systemImage: "calendar.day.timeline.left") }
            syncTab
                .tabItem { Label("Sync-Server", systemImage: "icloud") }
            maintenanceTab
                .tabItem { Label("Wartung", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560, height: 480)
        .onAppear { loadCredentials() }
    }

    // MARK: - Tabs

    private var generalTab: some View {
        Form {
            Section {
                Picker("Sprache", selection: $language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang.rawValue)
                    }
                }
            } header: {
                Text("Sprache").font(.headline)
            } footer: {
                Text("Sprachwechsel wird nach App-Neustart wirksam.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("Beim Start zeigen", selection: $defaultFilter) {
                    ForEach(DefaultFilter.allCases) { f in
                        Text(f.label).tag(f.rawValue)
                    }
                }
                Picker("Sortierung", selection: $defaultSort) {
                    ForEach(SortOrder.allCases) { s in
                        Text(s.label).tag(s.rawValue)
                    }
                }
            } header: {
                Text("Standardansicht").font(.headline)
            }

            Section {
                Toggle("Farbige Symbole in der Seitenleiste", isOn: $sidebarColoredIcons)
                Toggle("Projekte hierarchisch anzeigen", isOn: $sidebarProjectHierarchy)
            } header: {
                Text("Darstellung").font(.headline)
            } footer: {
                Text("Aus: Symbole erscheinen einfarbig wie Projekt- und Tag-Einträge. Bei deaktivierter Hierarchie erscheinen Projekte als flache Liste mit vollständigen Punkt-Namen (z. B. \"Arbeit.KundeA\").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("Bei überfälligen Aufgaben benachrichtigen", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue {
                            Task { await NotificationService.shared.requestAuthorizationIfNeeded() }
                        }
                    }
            } header: {
                Text("Benachrichtigungen").font(.headline)
            } footer: {
                Text("Bei aktivierter Option zeigt die App nach dem Start eine Zusammenfassung der überfälligen Aufgaben.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Stepper(value: $dueSoonDays, in: 1...60) {
                    Text(String(localized: "\(dueSoonDays) Tag"))
                }
            } header: {
                Text("Bald fällig").font(.headline)
            } footer: {
                Text("Tasks innerhalb dieses Fensters erscheinen unter \"Bald fällig\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("Automatisch synchronisieren", selection: $autoSyncMode) {
                    ForEach(AutoSyncMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
            } header: {
                Text("Synchronisation").font(.headline)
            } footer: {
                Text("Bei \"Bei jeder Änderung\" wird nach jeder Mutation ein Sync ausgelöst. Timer-Modi synchronisieren im Hintergrund. Manuell erfordert den Sync-Button in der Toolbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var forecastTab: some View {
        Form {
            Section {
                ForEach(ForecastPerspective.allCases) { perspective in
                    perspectiveRow(perspective)
                }
            } header: {
                Text("Pro Perspektive").font(.headline)
            } footer: {
                Text("Jede Seitenleisten-Perspektive hat eine eigene Vorschau. \"Agenda\" gruppiert nach Tag mit Projekt-Untertitel, \"Kompakt\" zeigt einen Wochen-Streifen (bei mehreren Wochen je Woche eine Zeile). \"Aus\" blendet die Vorschau in dieser Perspektive aus. Aufgaben mit Plantermin (scheduled) erscheinen als \"geplant\". Kalenderwochen folgen der ISO-Norm (Montag-erste Woche). \"Projekte, Tags & gespeicherte Suchen\" gilt für alle dynamischen Perspektiven gemeinsam; in den Abhängigkeits-Berichten und im Kalender wird die Vorschau nie gezeigt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    /// Eine Perspektiven-Zeile: Darstellung-Picker; bei „nicht Aus" zusätzlich
    /// Zeitraum, Aufgaben pro Tag (nur Agenda) und Kalenderwochen — eingerückt.
    @ViewBuilder
    private func perspectiveRow(_ perspective: ForecastPerspective) -> some View {
        let config = configBinding(perspective)
        Picker(perspective.label, selection: config.display) {
            ForEach(ForecastDisplayMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        if config.wrappedValue.display != .off {
            Group {
                Picker("Zeitraum", selection: config.range) {
                    ForEach(ForecastRange.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
                if config.wrappedValue.display == .agenda {
                    Picker("Aufgaben pro Tag", selection: config.maxPerDay) {
                        ForEach(ForecastMaxPerDay.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                }
                Toggle("Kalenderwochen anzeigen", isOn: config.showCalendarWeeks)
            }
            .padding(.leading, 16)
        }
    }

    /// Binding für die `ForecastConfig` einer Perspektive, gespiegelt auf das
    /// JSON-Dictionary in `@AppStorage`. Lesen fällt bei fehlendem Eintrag auf den
    /// perspektiven-spezifischen Default; Schreiben aktualisiert nur diesen Eintrag.
    private func configBinding(_ perspective: ForecastPerspective) -> Binding<ForecastConfig> {
        Binding(
            get: { ForecastConfig.resolve(perspective, from: forecastConfigsRaw) },
            set: { forecastConfigsRaw = ForecastConfig.update(perspective, to: $0, in: forecastConfigsRaw) }
        )
    }

    private var syncTab: some View {
        Form {
            Section {
                TextField("Server-URL", text: $serverUrl)
                TextField("Client-ID", text: $clientId)
                SecureField("Encryption Secret", text: $encryptionSecret)
            } header: {
                Text("Sync-Server").font(.headline)
            }

            Section {
                HStack {
                    Button("Speichern") { saveCredentials() }
                        .buttonStyle(.borderedProminent)
                    Button("Test-Sync") {
                        Task { await runTestSync() }
                    }
                }
            }

            if let msg = statusMessage {
                Section {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(msg.hasPrefix("✓") ? Color.green : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var maintenanceTab: some View {
        Form {
            Section {
                HStack {
                    Button("Backup erstellen") {
                        Task { await runManualBackup() }
                    }
                    Button("Backups öffnen …") {
                        NSWorkspace.shared.open(backupsURL)
                    }
                    Button("Aus Backup wiederherstellen …") {
                        showRestorePicker = true
                    }
                }
            } header: {
                Text("Datensicherung").font(.headline)
            } footer: {
                Text("Vor jedem Sync wird automatisch ein Backup angelegt (rotierend, letzte 10 Stände werden behalten). Manuell kann jederzeit ein zusätzliches Backup erzeugt oder ein bestehendes Backup als aktive Replica eingespielt werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button("Legacy-Tasks reparieren") {
                    Task { await runRepair() }
                }
            } header: {
                Text("Wartung").font(.headline)
            } footer: {
                Text("Parst alte Descriptions mit +tag / project:foo / due:bar und schreibt sie als Properties zurück. Tasks mit bereits gesetzten Metadaten bleiben unangetastet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let msg = statusMessage {
                Section {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(msg.hasPrefix("✓") ? Color.green : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showRestorePicker) {
            BackupRestoreSheet(
                backupService: container.backupService,
                onRestored: {
                    statusMessage = String(localized: "✓ Restore — App-Neustart empfohlen")
                }
            )
        }
    }

    private var backupsURL: URL {
        container.backupService.backupsURL
    }

    // MARK: - Private

    private func loadCredentials() {
        serverUrl        = KeychainStore.load(key: .serverUrl) ?? ""
        clientId         = KeychainStore.load(key: .clientId) ?? ""
        encryptionSecret = KeychainStore.load(key: .encryptionSecret) ?? ""
    }

    private func saveCredentials() {
        do {
            try KeychainStore.save(serverUrl,        for: .serverUrl)
            try KeychainStore.save(clientId,         for: .clientId)
            try KeychainStore.save(encryptionSecret, for: .encryptionSecret)
            container.updateSyncConfigured()
            statusMessage = String(localized: "✓ Gespeichert")
        } catch {
            statusMessage = String(localized: "Fehler beim Speichern: \(error.localizedDescription)")
        }
    }

    private func runManualBackup() async {
        statusMessage = String(localized: "Sichere …")
        let service = container.backupService
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try service.createBackup(reason: "manual")
            }.value
            statusMessage = String(localized: "✓ Backup: \(url.lastPathComponent)")
        } catch {
            statusMessage = String(localized: "Fehler: \(error.localizedDescription)")
        }
    }

    private func runRepair() async {
        statusMessage = String(localized: "Repariere …")
        let count = await container.repairLegacyTasks()
        if let err = container.lastError {
            statusMessage = String(localized: "Fehler: \(err)")
        } else {
            statusMessage = "✓ " + String(localized: "\(count) Task repariert")
        }
    }

    private func runTestSync() async {
        statusMessage = String(localized: "Verbinde …")
        await container.sync(
            serverUrl:        serverUrl,
            clientId:         clientId,
            encryptionSecret: encryptionSecret
        )
        if let err = container.lastError {
            statusMessage = String(localized: "Fehler: \(err)")
        } else {
            statusMessage = String(localized: "✓ Sync")
        }
    }
}
