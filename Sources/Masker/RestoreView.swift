import SwiftUI
import UniformTypeIdentifiers
import MaskerCore

struct RestoreView: View {
    @EnvironmentObject var appState: AppState

    @State private var inputText: String = ""
    @State private var restoredText: String = ""
    @State private var statusMessage: String = ""
    @State private var isDragTarget = false
    @State private var showingMappingImport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                Text("文本还原")
                    .font(.title2).bold()
                Text("— 将 🔒UUID🔒 恢复为原始敏感信息")
                    .foregroundColor(.secondary)
            }

            // Status bar showing mapping count
            HStack {
                Label("当前映射表: \(appState.store.count) 项", systemImage: "map")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
                Button("📂 导入映射 JSON") {
                    importMappingFile()
                }
                .buttonStyle(.bordered)
                if appState.store.count > 0 {
                    Button("🗑️ 清空映射") {
                        appState.store.clear()
                        statusMessage = "🗑️ 映射表已清空"
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
            }

            // Instructions
            Text("粘贴 AI 处理后的文本（含 🔒UUID🔒 占位符），应用会自动替换为原始信息")
                .font(.callout)
                .foregroundColor(.secondary)

            // Input area
            Text("AI 处理后文本")
                .font(.headline)

            TextEditor(text: $inputText)
                .font(.body)
                .frame(minHeight: 140)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isDragTarget ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isDragTarget ? 2 : 1)
                )
                .overlay(alignment: .center) {
                    if inputText.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.largeTitle)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("粘贴 AI 返回的文本")
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [.plainText, .fileURL], isTargeted: $isDragTarget) { providers in
                    handleDrop(providers)
                    return true
                }

            // Actions
            HStack(spacing: 12) {
                Button("执行还原", action: runRestore)
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("清空", role: .destructive) {
                    inputText = ""
                    restoredText = ""
                    statusMessage = ""
                }
                .disabled(inputText.isEmpty && restoredText.isEmpty)

                Spacer()

                Button("📋 粘贴") {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        inputText = str
                    }
                }
            }

            // Status
            if !statusMessage.isEmpty {
                if statusMessage.contains("❌") {
                    Label(statusMessage, systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.callout)
                } else {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.callout)
                }
            }

            // Result
            if !restoredText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("还原结果")
                            .font(.headline)
                        Spacer()
                        Button("📋 复制结果") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(restoredText, forType: .string)
                            statusMessage = "✅ 已复制到剪贴板"
                        }
                        .buttonStyle(.bordered)
                        Button("💾 保存到文件") {
                            saveToFile(restoredText)
                        }
                        .buttonStyle(.bordered)
                    }

                    ScrollView {
                        Text(restoredText)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                    }
                    .frame(maxHeight: 200)
                }
                .padding(.top, 8)
            }
        }
    }

    // ── Actions ──

    private func runRestore() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if appState.store.count == 0 {
            statusMessage = "❌ 映射表为空！请先导入映射 JSON 文件或在脱敏页面生成映射"
            return
        }

        let result = appState.store.restore(inputText)

        if result == inputText {
            // Check if there are any UUID placeholders
            if inputText.contains("🔒") {
                statusMessage = "⚠️ 文本中的一些 UUID 在映射表中未找到，可能缺少对应的映射文件"
            } else {
                statusMessage = "⚠️ 未检测到可还原的 UUID 占位符"
            }
        } else {
            let replaceCount = countReplacements(original: inputText, restored: result)
            statusMessage = "✅ 已还原 \(replaceCount) 处敏感信息"
        }

        restoredText = result
    }

    private func countReplacements(original: String, restored: String) -> Int {
        // Simple heuristic: each UUID replacement is a segment difference
        let origPlaceholders = original.matches(of: try! Regex("🔒[A-Z0-9]{8}🔒"))
        return origPlaceholders.count
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        if url.pathExtension == "json" {
                            // Import mapping
                            if let json = try? String(contentsOf: url, encoding: .utf8) {
                                if self.appState.store.importJSON(json) {
                                    self.statusMessage = "📂 映射表已导入（\(url.lastPathComponent)）"
                                } else {
                                    self.statusMessage = "❌ 映射文件格式错误"
                                }
                            }
                        } else {
                            self.loadFile(url)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    if let str = item as? String {
                        DispatchQueue.main.async {
                            self.inputText = str
                        }
                    }
                }
            }
        }
    }

    private func importMappingFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let json = try? String(contentsOf: url, encoding: .utf8) {
                    if appState.store.importJSON(json) {
                        statusMessage = "📂 映射表已导入（共 \(appState.store.count) 项）"
                    } else {
                        statusMessage = "❌ 映射文件格式错误"
                    }
                }
            }
        }
    }

    private func loadFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) ??
                        String(data: data, encoding: .utf16) else {
            statusMessage = "❌ 无法读取文件"
            return
        }
        inputText = str
        statusMessage = "📂 已加载 \(url.lastPathComponent)"
    }

    private func saveToFile(_ text: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "restored.txt"
        panel.allowedContentTypes = [.plainText]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "💾 已保存到 \(url.lastPathComponent)"
            }
        }
    }
}
