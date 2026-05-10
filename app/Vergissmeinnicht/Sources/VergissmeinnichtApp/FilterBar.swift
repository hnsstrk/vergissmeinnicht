import SwiftUI

/// Sidebar-Header mit Volltext-Suchfeld.
///
/// Filtert clientseitig die Description (siehe `TaskListViewModel.visibleTasks`).
/// Project-/Tag-Filter folgen, sobald die FFI diese Felder exportiert.
struct FilterBar: View {
    @Binding var searchQuery: String

    var body: some View {
        TextField("Suchen…", text: $searchQuery)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}
