import SwiftUI
import Core

public struct TemplatePickerView: View {
    public let templates: [Template]
    public let onSelect: (Template) -> Void

    public init(templates: [Template] = BuiltInTemplates.all, onSelect: @escaping (Template) -> Void) {
        self.templates = templates
        self.onSelect = onSelect
    }

    public var body: some View {
        Menu {
            ForEach(templates) { template in
                Button {
                    onSelect(template)
                } label: {
                    VStack(alignment: .leading) {
                        Text(template.name)
                        Text(template.description).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "plus.rectangle.on.rectangle")
                Text("New Session from Template…")
                Spacer()
            }
        }
        .menuStyle(.borderlessButton)
    }
}
