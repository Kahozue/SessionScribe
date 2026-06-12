import SSCore
import SwiftUI

/// 分類管理（規格 1.1 第 7 項）：自訂名稱、隱藏、刪除、新增。
struct CategoryManagerView: View {
    let model: RecordingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("管理分類")
                .font(.headline)
            if model.libraryConfig.categories.isEmpty {
                Text("尚無分類。新增後可在側欄把 session 拖入或用右鍵選單移動。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                List(model.libraryConfig.categories) { category in
                    HStack(spacing: 8) {
                        TextField(
                            "名稱",
                            text: Binding(
                                get: { category.name },
                                set: { model.renameCategory(id: category.id, to: $0) }))
                        Spacer()
                        Toggle(
                            "隱藏",
                            isOn: Binding(
                                get: { category.hidden },
                                set: { _ in model.toggleCategoryHidden(id: category.id) }))
                        .toggleStyle(.checkbox)
                        Button(role: .destructive) {
                            model.deleteCategory(id: category.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("刪除分類（session 移回未分類）")
                    }
                }
                .frame(minHeight: 160)
            }
            HStack {
                TextField("新分類名稱", text: $newName)
                    .onSubmit(addCategory)
                Button("新增", action: addCategory)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func addCategory() {
        model.addCategory(name: newName)
        newName = ""
    }
}
