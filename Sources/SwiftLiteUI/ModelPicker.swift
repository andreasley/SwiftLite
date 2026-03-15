#if canImport(SwiftUI)
import SwiftUI

struct ModelPicker<Item: Identifiable & Equatable & Hashable, Label: View>: View
{
    @Binding var selection: Item?

    let titleKey: String
    let items: [Item]
    let label: (Item) -> Label

    init(_ titleKey: String, items: [Item], selection: Binding<Item?>, label: @escaping (Item) -> Label)
    {
        self.titleKey = titleKey
        self.items = items
        self._selection = selection
        self.label = label
    }

    init(_ titleKey: String, items: [Item], selection: Binding<Item>, label: @escaping (Item) -> Label)
    {
        self.titleKey = titleKey
        self.items = items
        self._selection = Binding(
            get: { selection.wrappedValue },
            set: { selection.wrappedValue = $0! }
        )
        self.label = label
    }

    var body: some View {
        Picker(titleKey, selection: resolvedSelection) {
            ForEach(items) { item in
                label(item).tag(Optional(item))
            }
        }
    }

    private var resolvedSelection: Binding<Item?> {
        Binding(
            get: { items.first { $0.id == selection?.id } },
            set: { selection = $0 }
        )
    }
}
#endif
