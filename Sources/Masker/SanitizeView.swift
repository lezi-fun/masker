import SwiftUI
import UniformTypeIdentifiers
import MaskerCore

struct SanitizeView: View {
    @EnvironmentObject var appState: AppState

    @State private var inputText: String = ""
    @State private var sanitizedText: String = ""
    @State private var newMappings: [(uuid: String, original: String, type: SensitiveType)] = []
    @State private var statusMessage: String = ""
    @State private var showingJSONExport = false
    @State private var jsonExportText: String = ""
    @State private var isDragTarget = false
    @State private var useAIDetection = false

    private var isAILoading: Bool {
#if !NO_AI
        appState.aiDetector.isLoading
#else
        false
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            HStack {
                Image(systemName: "lock.shield")
                    .font(.title2)
                Text("文本脱敏")
                    .font(.title2).bold()
                Text("— 将敏感信息替换为 🔒UUID🔒 占位符")
                    .foregroundColor(.secondary)
            }

            // Instructions
            Text("粘贴或拖入文本，敏感信息会自动识别并替换为 UUID 占位符")
                .font(.callout)
                .foregroundColor(.secondary)

            // AI 增强检测 toggle
#if !NO_AI
            HStack {
                Toggle(isOn: $useAIDetection) {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.head.profile")
                        Text("AI 增强检测 (OpenAI Privacy Filter)")
                    }
                }
                .toggleStyle(.switch)

                if appState.aiDetector.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(.leading, 4)
                }

                if !appState.aiDetector.statusMessage.isEmpty {
                    Text(appState.aiDetector.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !appState.aiDetector.isAvailable {
                    Text("⚠️ 未安装")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
#endif

            // Input area
            Text("输入文本")
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
                            Image(systemName: "doc.text")
                                .font(.largeTitle)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("拖入文件或粘贴文本")
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
                Button("执行脱敏", action: { Task { await runSanitize() } })
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAILoading)

                Button("清空", role: .destructive) {
                    inputText = ""
                    sanitizedText = ""
                    newMappings = []
                    statusMessage = ""
                }
                .disabled(inputText.isEmpty && sanitizedText.isEmpty)

                Spacer()

                Button("📋 粘贴") {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        inputText = str
                    }
                }

                Button("📂 打开文件") {
                    openFile()
                }
            }

            // Status
            if !statusMessage.isEmpty {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.callout)
            }

            // Results
            if !sanitizedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("脱敏结果")
                            .font(.headline)
                        Spacer()
                        Button("📋 复制结果") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(sanitizedText, forType: .string)
                            statusMessage = "✅ 已复制到剪贴板"
                        }
                        .buttonStyle(.bordered)
                    }

                    ScrollView {
                        Text(sanitizedText)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                    }
                    .frame(maxHeight: 160)

                    // Mapping table
                    if !newMappings.isEmpty {
                        HStack {
                            Text("脱敏映射表")
                                .font(.headline)
                            Spacer()
                            Text("共 \(newMappings.count) 项")
                                .foregroundColor(.secondary)
                            Button("📋 导出映射 JSON") {
                                jsonExportText = appState.store.exportJSON()
                                showingJSONExport = true
                            }
                            .buttonStyle(.bordered)
                        }

                        TableView(mappings: newMappings)
                            .frame(minHeight: 100, maxHeight: 200)
                            .cornerRadius(6)
                    }
                }
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showingJSONExport) {
            VStack(spacing: 16) {
                Text("映射 JSON（保存此文件以还原）")
                    .font(.headline)
                TextEditor(text: .constant(jsonExportText))
                    .font(.body.monospaced())
                    .frame(minWidth: 400, minHeight: 300)
                    .border(Color.gray.opacity(0.2))
                HStack {
                    Button("📋 复制") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(jsonExportText, forType: .string)
                    }
                    Button("💾 保存到文件") {
                        saveJSONToFile(jsonExportText)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("关闭", role: .cancel) {
                        showingJSONExport = false
                    }
                }
                .padding(.bottom)
            }
            .padding()
            .frame(width: 520, height: 420)
        }
    }

    // ── Actions ──

    @MainActor
    private func runSanitize() async {
        let text = inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Step 1: Run regex detection
        let regexSegments = appState.detector.detect(in: text)
        var allSegments: [SensitiveSegment] = []
        var aiInfo: String = ""

        // Step 2: Run AI detection if enabled
#if !NO_AI
        if useAIDetection {
            appState.aiDetector.reset()
            let aiResults = await appState.aiDetector.detect(text: text)

            // Convert AI segments to SensitiveSegment format, skip low confidence
            let threshold = 0.7
            for ai in aiResults where ai.confidence >= threshold && !ai.original.isEmpty {
                let nsRange = NSRange(location: ai.start, length: ai.end - ai.start)
                allSegments.append(SensitiveSegment(
                    original: ai.original,
                    range: nsRange,
                    type: ai.type
                ))
            }

            aiInfo = " + AI \(aiResults.filter { $0.confidence >= threshold }.count) 项"
        }
#endif

        // Merge: regex segments first (they're more precise for what they cover)
        allSegments = regexSegments + allSegments

        // Remove overlapping (prefer longer/regex first)
        let merged = mergeSegments(allSegments)

        if merged.isEmpty {
            statusMessage = "⚠️ 未检测到敏感信息"
            sanitizedText = ""
            newMappings = []
            return
        }

        // Run sanitization
        let (result, mappings) = appState.store.sanitize(text, segments: merged)
        sanitizedText = result
        newMappings = mappings

        let typeSummary = Dictionary(grouping: mappings, by: \.type)
            .map { "\($0.key.rawValue) ×\($0.value.count)" }
            .joined(separator: "、")
        statusMessage = "✅ 检测到 \(mappings.count) 项敏感信息：\(typeSummary)\(aiInfo)"
    }

    /// Merge segments: prefer regex (earlier in array) over AI, deduplicate by range
    private func mergeSegments(_ segments: [SensitiveSegment]) -> [SensitiveSegment] {
        var result: [SensitiveSegment] = []
        var usedRanges: [NSRange] = []

        for seg in segments {
            // Check if this segment overlaps with any already-used segment
            let overlaps = usedRanges.contains { used in
                let a = seg.range
                let b = used
                return a.location < b.location + b.length && a.location + a.length > b.location
            }
            if !overlaps {
                result.append(seg)
                usedRanges.append(seg.range)
            }
        }

        return result.sorted { $0.range.location < $1.range.location }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        Task { await self.loadFile(url) }
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

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .plainText, .text, .log, .json, .xml, .yaml, .commaSeparatedText,
            .pdf,
        ]
        panel.allowsOtherFileTypes = true  // allow docx, xlsx via "all files"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { await self.loadFile(url) }
            }
        }
    }

    @MainActor
    private func loadFile(_ url: URL) async {
        statusMessage = "📂 读取 \(url.lastPathComponent)..."

        // Try direct plain text read first
        if appState.fileExtractor.isPlainText(url),
           let text = appState.fileExtractor.readPlainText(url) {
            inputText = text
            statusMessage = "📂 已加载 \(url.lastPathComponent)"
            return
        }

        // Use Python extractor for binary formats
        let ext = url.pathExtension.lowercased()
        let formatName: String = {
            switch ext {
            case "docx": return "Word 文档"
            case "pdf": return "PDF 文档"
            case "xlsx", "xls": return "Excel 表格"
            case "csv": return "CSV 文件"
            default: return "文件"
            }
        }()

        statusMessage = "⏳ 正在提取 \(formatName) 文本..."
        guard let text = await appState.fileExtractor.extract(url) else {
            statusMessage = "❌ 无法读取 \(url.lastPathComponent)"
            return
        }

        inputText = text
        statusMessage = "📂 已加载 \(url.lastPathComponent)（\(formatName)，\(text.count) 字符）"
    }

    private func saveJSONToFile(_ json: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "masker-mapping.json"
        panel.allowedContentTypes = [.json]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? json.write(to: url, atomically: true, encoding: .utf8)
                self.statusMessage = "💾 映射已保存到 \(url.lastPathComponent)"
                self.showingJSONExport = false
            }
        }
    }
}

/// Simple table-like view for mappings
struct TableView: View {
    let mappings: [(uuid: String, original: String, type: SensitiveType)]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("UUID")
                        .frame(width: 90, alignment: .leading)
                        .font(.caption.bold())
                    Text("原始值")
                        .frame(width: 160, alignment: .leading)
                        .font(.caption.bold())
                    Text("类型")
                        .frame(width: 100, alignment: .leading)
                        .font(.caption.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))

                Divider()

                // Rows
                ForEach(Array(mappings.enumerated()), id: \.offset) { _, m in
                    HStack {
                        Text("🔒\(m.uuid)🔒")
                            .frame(width: 90, alignment: .leading)
                            .font(.caption.monospaced())
                        Text(m.original)
                            .frame(width: 160, alignment: .leading)
                            .font(.caption)
                        Text(m.type.rawValue)
                            .frame(width: 100, alignment: .leading)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Divider()
                }
            }
        }
    }
}
