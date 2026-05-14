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
        let entries: [Entry]
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
                Entry(label: "Aktualisieren",          keys: "⌘R"),
                Entry(label: "Synchronisieren",        keys: "⇧⌘S"),
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
