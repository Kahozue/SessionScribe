import SSCore
import SwiftUI

/// 匯出選項視窗：任何匯出入口都先經過這裡，勾選要輸出的格式再選位置。
struct ExportOptionsView: View {
    let session: Session
    let onExport: (Set<ExportFormat>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<ExportFormat> = Set(ExportFormat.allCases)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("匯出「\(session.title)」")
                .font(.headline)
            Text("選擇要匯出的內容：")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ExportFormat.allCases) { format in
                    Toggle(format.displayName, isOn: binding(for: format))
                        .toggleStyle(.checkbox)
                }
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("選擇位置並匯出…") {
                    dismiss()
                    onExport(selected)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private func binding(for format: ExportFormat) -> Binding<Bool> {
        Binding(
            get: { selected.contains(format) },
            set: { include in
                if include {
                    selected.insert(format)
                } else {
                    selected.remove(format)
                }
            })
    }
}
