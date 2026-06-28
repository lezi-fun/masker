#if !NO_AI
import Foundation

/// Runs OpenAI Privacy Filter model via Python subprocess
public class PrivacyFilterRunner: ObservableObject {
    @Published public var isAvailable: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var statusMessage: String = ""

    private let scriptPath: String
    private let pythonPath: String
    private let modelDir: String

    public init() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // ── 判断运行环境：.app bundle 还是开发模式 ──
        if let bundlePath = Bundle.main.resourcePath {
            // 在 .app 内：模型在 Resources/ai-model/
            let bundledModel = "\(bundlePath)/ai-model"
            if fm.fileExists(atPath: "\(bundledModel)/model.safetensors") {
                modelDir = bundledModel
                scriptPath = "\(bundlePath)/privacy_filter.py"
                pythonPath = "\(bundlePath)/.venv/bin/python"
            } else {
                // 开发模式
                modelDir = "\(home)/projects/masker/ai-model"
                scriptPath = "\(home)/projects/masker/privacy_filter.py"
                pythonPath = "\(home)/projects/masker/.venv/bin/python"
            }
        } else {
            modelDir = "\(home)/projects/masker/ai-model"
            scriptPath = "\(home)/projects/masker/privacy_filter.py"
            pythonPath = "\(home)/projects/masker/.venv/bin/python"
        }

        checkAvailability()
    }

    /// Check if the Python venv, script, and model exist
    private func checkAvailability() {
        let fm = FileManager.default
        let hasScript = fm.fileExists(atPath: scriptPath)
        let hasPython = fm.fileExists(atPath: pythonPath)
        let hasModel = fm.fileExists(atPath: "\(modelDir)/model.safetensors")
        isAvailable = hasScript && hasPython && hasModel
    }

    /// Run Privacy Filter detection. Returns parsed segments or nil on failure.
    public func detect(text: String) async -> [AISegment] {
        guard isAvailable else {
            await MainActor.run { self.statusMessage = "⚠️ AI 模型未就绪（需完整版）" }
            return []
        }

        await MainActor.run {
            self.isLoading = true
            self.statusMessage = "🤖 AI 检测中..."
        }

        let result = await runProcess(input: text)

        await MainActor.run {
            self.isLoading = false
        }

        guard let data = result.data(using: .utf8) else {
            await MainActor.run { self.statusMessage = "❌ AI 输出解析失败" }
            return []
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let spansArray = json["spans"] as? [[String: Any]] else {
                await MainActor.run { self.statusMessage = "❌ AI 返回格式错误" }
                return []
            }

            var segments: [AISegment] = []
            for s in spansArray {
                guard let text = s["text"] as? String,
                      let label = s["label"] as? String,
                      let start = s["start"] as? Int,
                      let end = s["end"] as? Int,
                      let score = s["score"] as? Double else {
                    continue
                }

                let mappedType = mapLabel(label)

                segments.append(AISegment(
                    original: text.trimmingCharacters(in: .whitespaces),
                    type: mappedType,
                    confidence: score,
                    start: start,
                    end: end
                ))
            }

            let count = segments.count
            await MainActor.run {
                self.statusMessage = "🤖 AI 检测到 \(count) 处敏感信息"
            }
            return segments

        } catch {
            await MainActor.run { self.statusMessage = "❌ AI JSON 解析错误: \(error.localizedDescription)" }
            return []
        }
    }

    private func runProcess(input: String) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.pythonPath)
                process.arguments = [self.scriptPath, "--model-dir", self.modelDir, input]

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                        let lines = output.components(separatedBy: "\n")
                            .filter { !$0.hasPrefix("[pf]") && !$0.hasPrefix("Warning:") && !$0.hasPrefix("\r") && !$0.contains("%|") }
                        continuation.resume(returning: lines.joined(separator: "\n"))
                    } else if let error = String(data: errorData, encoding: .utf8) {
                        continuation.resume(returning: "{\"error\": \"\(error)\", \"spans\": []}")
                    } else {
                        continuation.resume(returning: "{\"error\": \"No output\", \"spans\": []}")
                    }
                } catch {
                    continuation.resume(returning: "{\"error\": \"\(error.localizedDescription)\", \"spans\": []}")
                }
            }
        }
    }

    private func mapLabel(_ label: String) -> SensitiveType {
        switch label {
        case "private_person": return .name
        case "private_address": return .address
        case "private_email": return .email
        case "private_phone": return .phone
        case "private_url": return .url
        case "private_date": return .date
        case "private_account": return .bankCard
        case "private_key": return .key
        case "account_number": return .bankCard
        case "secret": return .key
        default: return .custom
        }
    }

    public func reset() {
        statusMessage = ""
        isLoading = false
    }
}

/// Segment detected by AI model
public struct AISegment: Identifiable {
    public let id = UUID()
    public let original: String
    public let type: SensitiveType
    public let confidence: Double
    public let start: Int
    public let end: Int

    public init(original: String, type: SensitiveType, confidence: Double, start: Int, end: Int) {
        self.original = original
        self.type = type
        self.confidence = confidence
        self.start = start
        self.end = end
    }
}
#endif
