import SwiftUI

/// Schlanke About-Ansicht. Wird via WindowGroup `about` aus dem App-Menü geöffnet.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Vergissmeinnicht")
                .font(.title2.bold())
            Text("Nativer macOS-Client für Taskwarrior 3.x.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
               let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                Text(verbatim: "v\(version) (\(build))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(width: 340)
    }
}

/// Hilfe-Sheet mit Tastenkürzel-Übersicht. Sektionen nach Wirkungsbereich gruppiert.
struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry {
        let label: LocalizedStringKey
        let keys: String
    }

    private struct Section {
        let title: LocalizedStringKey
        let note: LocalizedStringKey?
        let entries: [Entry]

        init(title: LocalizedStringKey, note: LocalizedStringKey? = nil, entries: [Entry]) {
            self.title = title
            self.note = note
            self.entries = entries
        }
    }

    private var sections: [Section] {
        [
            Section(title: "Aufgaben", entries: [
                Entry(label: "Neue Aufgabe",           keys: "⌘N"),
                Entry(label: "Als erledigt markieren", keys: "⌘D"),
                Entry(label: "Löschen",                keys: "⌘⌫"),
                Entry(label: "Detail öffnen",          keys: "↩"),
            ]),
            Section(title: "Ansicht", entries: [
                Entry(label: "Suchen…",                keys: "⌘F"),
                Entry(label: "Suche sichern",          keys: "⇧⌘D"),
                Entry(label: "Aktualisieren",          keys: "⌘R"),
                Entry(label: "Synchronisieren",        keys: "⇧⌘S"),
                Entry(label: "Erledigte ausblenden",   keys: "⇧⌘H"),
                Entry(label: "Detailspalte anzeigen",  keys: "⌥⌘0"),
            ]),
            Section(title: "Detail-Editor", entries: [
                Entry(label: "Speichern",              keys: "⌘S"),
            ]),
            Section(title: "Fenster & App", entries: [
                Entry(label: "Einstellungen",          keys: "⌘,"),
                Entry(label: "Fenster schließen",      keys: "⌘W"),
                Entry(label: "Tastenkürzel",           keys: "⌘?"),
                Entry(label: "Beenden",                keys: "⌘Q"),
            ]),
            Section(title: "Maus & Trackpad", entries: [
                Entry(label: "Mehrfach-Auswahl",       keys: "⌘ + Klick"),
                Entry(label: "Bereich auswählen",      keys: "⇧ + Klick"),
                Entry(label: "Detail öffnen",          keys: "Doppelklick"),
                Entry(label: "Erledigt",               keys: "Swipe ▶ (grün)"),
                Entry(label: "Löschen",                keys: "Swipe ◀ (rot)"),
                Entry(label: "Auf Sidebar ziehen",     keys: "Drag → Projekt / Tag / Eingang"),
            ]),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tastenkürzel")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            if let note = section.note {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 2)
                            }
                            ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                                HStack {
                                    Text(entry.label)
                                    Spacer()
                                    Text(entry.keys)
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 540)
    }
}

/// Dediziertes Hilfe-Sheet für die Suchfunktion. Erreichbar über das Hilfe-Menü
/// (eigener Eintrag „Suche-Hilfe"). Karpathy 2: ein eigenes Sheet pro Hilfe-Thema —
/// Tastenkürzel und Suche werden bewusst nicht vermischt.
struct SearchHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Suche-Hilfe")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bei aktiver Suche wird der Sidebar-Filter ignoriert. Die Suche umfasst Titel, Projekt, Tags und Annotationen über den gesamten Bestand (offene, erledigte, wiederkehrende Aufgaben). Mehrere Wörter sind UND-verknüpft. Werte mit Leerzeichen in Anführungszeichen setzen: projekt:\"Mein Projekt\".")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Operatoren")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("Operator").font(.caption.bold()).foregroundStyle(.tertiary)
                            Text("Funktion").font(.caption.bold()).foregroundStyle(.tertiary)
                            Text("Beispiel").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        GridRow {
                            Text(verbatim: "projekt:  project:")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("Passt auf Projektname")
                            exampleChip(String(localized: "projekt:arbeit"))
                        }
                        GridRow {
                            Text(verbatim: "tag:")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("Passt auf Tag")
                            exampleChip(String(localized: "tag:dringend"))
                        }
                        GridRow {
                            Text(verbatim: "status:")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Filtert nach Status")
                                Text(String(localized: "offen · erledigt · wiederkehrend · gelöscht"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            exampleChip(String(localized: "status:erledigt"))
                        }
                    }

                    Text("Gespeicherte Suchen")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    Text("Gespeicherte Suchen: Aktive Suchen mit ⇧⌘D sichern. Erscheinen in der Sidebar zwischen System-Filtern und Projekten. Rechtsklick: Umbenennen oder Löschen.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
            HStack {
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 460)
    }

    @ViewBuilder
    private func exampleChip(_ text: String) -> some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}
