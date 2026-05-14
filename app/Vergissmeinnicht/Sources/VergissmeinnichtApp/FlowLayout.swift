import SwiftUI

/// Einfaches Flow-Layout: ordnet Subviews zeilenweise von links nach rechts an;
/// bei Überschreiten der verfügbaren Breite umbricht in eine neue Zeile.
/// Wird für Meta-Chips in `TaskRowView` genutzt, damit ALLE Tags / Project /
/// Due / Wait / Recur sichtbar bleiben statt rechts abzubrechen.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(CGFloat(0)) { acc, row in
            acc + row.height + (acc > 0 ? verticalSpacing : 0)
        }
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let maxWidth = bounds.width
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let current = rows[rows.count - 1]
            let proposedWidth = current.width + (current.indices.isEmpty ? 0 : horizontalSpacing) + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(Row(indices: [index], width: size.width, height: size.height))
            } else {
                var updated = current
                updated.indices.append(index)
                updated.width = proposedWidth
                updated.height = max(updated.height, size.height)
                rows[rows.count - 1] = updated
            }
        }
        return rows
    }
}
