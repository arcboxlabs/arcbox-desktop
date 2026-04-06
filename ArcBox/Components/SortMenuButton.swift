import SwiftUI

/// Generic sort menu button for toolbar usage
struct SortMenuButton<Field: Hashable & CaseIterable & RawRepresentable>: View
where Field.RawValue == String, Field.AllCases: RandomAccessCollection {
    @Binding var sortBy: Field
    @Binding var ascending: Bool

    var body: some View {
        Menu {
            Section("Sort By") {
                ForEach(Field.allCases, id: \.self) { field in
                    Button {
                        sortBy = field
                    } label: {
                        if sortBy == field {
                            Label(field.rawValue, systemImage: "checkmark")
                        } else {
                            Text(field.rawValue)
                        }
                    }
                }
            }
            Section("Order") {
                Button {
                    ascending = true
                } label: {
                    if ascending {
                        Label("Ascending", systemImage: "checkmark")
                    } else {
                        Text("Ascending")
                    }
                }
                Button {
                    ascending = false
                } label: {
                    if !ascending {
                        Label("Descending", systemImage: "checkmark")
                    } else {
                        Text("Descending")
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }
}
