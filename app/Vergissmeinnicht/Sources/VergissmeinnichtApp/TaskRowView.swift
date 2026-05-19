import SwiftUI
import VergissmeinnichtKit

/// Kompakte Listen-Zeile: ID (falls Pending), Description, Status-Indikator,
/// kleine Meta-Chips (Projekt, Tags, Due) als Beleg, dass die Felder persistiert sind.
///
/// Selection-/Hover-Highlight liefert die umgebende `List` automatisch.
struct TaskRowView: View {
    let task: TaskInfo

    var body: some View {
        HStack(spacing: 8) {
            if let id = task.workingSetId {
                Text("#\(id)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, alignment: .leading)
            } else {
                Text(" ")
                    .font(.system(.caption, design: .monospaced))
                    .frame(minWidth: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if task.status == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Text(task.description)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .strikethrough(task.status == .completed, color: .secondary)
                        .foregroundStyle(task.status == .completed ? Color.secondary : Color.primary)
                }
                if hasMeta {
                    metaRow
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    /// Zusammengesetzter VoiceOver-Text — semantische Information statt
    /// Icon-Namen. Reihenfolge: ID, Status, Titel, Projekt, Tags, Fälligkeit.
    private var a11yLabel: String {
        var parts: [String] = []
        if let id = task.workingSetId {
            parts.append(String(localized: "Aufgabe \(id)", comment: "VoiceOver: Aufgaben-Nummer"))
        }
        switch task.status {
        case .pending where TimeInterval(task.due ?? 0) < Date().timeIntervalSince1970 && task.due != nil:
            parts.append(String(localized: "überfällig", comment: "VoiceOver: Aufgaben-Status"))
        case .completed:
            parts.append(String(localized: "erledigt", comment: "VoiceOver: Aufgaben-Status"))
        default:
            break
        }
        parts.append(task.description)
        if let project = task.project {
            parts.append(String(localized: "Projekt \(project)", comment: "VoiceOver: Projekt-Name"))
        }
        if !task.tags.isEmpty {
            parts.append(String(localized: "Tags: \(task.tags.joined(separator: ", "))", comment: "VoiceOver: Tag-Liste"))
        }
        if let due = task.due {
            let d = Date(timeIntervalSince1970: TimeInterval(due))
            parts.append(String(localized: "fällig \(d.formatted(date: .abbreviated, time: .omitted))", comment: "VoiceOver: Fälligkeitsdatum"))
        }
        return parts.joined(separator: ", ")
    }

    private var hasMeta: Bool {
        task.project != nil || !task.tags.isEmpty || task.due != nil || task.wait != nil || task.recur != nil || task.scheduled != nil
    }

    private var isWaiting: Bool {
        guard let wait = task.wait else { return false }
        return TimeInterval(wait) > Date().timeIntervalSince1970
    }

    @ViewBuilder
    private var metaRow: some View {
        FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
            if let project = task.project {
                Label(project, systemImage: "folder")
                    .labelStyle(MetaChipStyle())
            }
            ForEach(task.tags.sorted(), id: \.self) { tag in
                Label(tag, systemImage: "tag")
                    .labelStyle(MetaChipStyle())
            }
            if let due = task.due {
                Label(formatted(due), systemImage: "clock")
                    .labelStyle(MetaChipStyle(tint: dueColor(due)))
            }
            if let wait = task.wait, isWaiting {
                Label("Wartet bis \(formatted(wait))", systemImage: "moon.zzz")
                    .labelStyle(MetaChipStyle(tint: .indigo))
            }
            if let recur = task.recur, !recur.isEmpty {
                Label(recur, systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(MetaChipStyle(tint: .purple))
            }
            if let scheduled = task.scheduled, isUpcoming(scheduled) {
                Label("Geplant ab \(formatted(scheduled))", systemImage: "calendar")
                    .labelStyle(MetaChipStyle(tint: .teal))
            }
        }
    }

    private func isUpcoming(_ unixSeconds: Int64) -> Bool {
        TimeInterval(unixSeconds) > Date().timeIntervalSince1970
    }

    private func formatted(_ unixSeconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        return date.formatted(date: .numeric, time: .omitted)
    }

    private func dueColor(_ unixSeconds: Int64) -> Color {
        let now = Date().timeIntervalSince1970
        if TimeInterval(unixSeconds) < now { return .red }
        if TimeInterval(unixSeconds) < now + 7 * 24 * 60 * 60 { return .orange }
        return .secondary
    }
}

/// Kompakter Chip-Stil für Metadaten in der Listenzeile.
private struct MetaChipStyle: LabelStyle {
    var tint: Color = .secondary

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
        .font(.caption2)
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(tint.opacity(0.12), in: Capsule())
    }
}
