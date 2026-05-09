import SwiftUI
import Core

public struct NewSessionMenu: View {
    @ObservedObject public var store: TemplateStore
    public let onRun: (Template) -> Void
    public let onOpenFolder: () -> Void
    public let onReload: () -> Void

    public init(
        store: TemplateStore,
        onRun: @escaping (Template) -> Void,
        onOpenFolder: @escaping () -> Void,
        onReload: @escaping () -> Void
    ) {
        self.store = store
        self.onRun = onRun
        self.onOpenFolder = onOpenFolder
        self.onReload = onReload
    }

    public var body: some View {
        Menu {
            Section(L.menuSectionBuiltIn) {
                ForEach(store.builtInTemplates) { template in
                    Button {
                        onRun(template)
                    } label: {
                        Text(template.name)
                    }
                }
            }

            if !store.userTemplates.isEmpty {
                Section(L.menuSectionCustom) {
                    ForEach(store.userTemplates) { template in
                        Button {
                            onRun(template)
                        } label: {
                            Text(template.name)
                        }
                    }
                }
            }

            Divider()
            Button(L.menuOpenTemplates) { onOpenFolder() }
            Button(L.menuReloadTemplates) { onReload() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.rectangle.on.rectangle")
                Text(L.menuNewSession)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
    }
}
