#if !NO_AI
import Foundation

/// Downloads and manages the AI model from HuggingFace
public class ModelDownloader: ObservableObject {
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = ""
    @Published public var isDownloading: Bool = false
    @Published public var isDownloaded: Bool = false

    private let files: [(name: String, url: String)] = [
        ("config.json", "https://huggingface.co/openai/privacy-filter/resolve/main/config.json"),
        ("tokenizer_config.json", "https://huggingface.co/openai/privacy-filter/resolve/main/tokenizer_config.json"),
        ("tokenizer.json", "https://huggingface.co/openai/privacy-filter/resolve/main/tokenizer.json"),
        ("model.safetensors", "https://huggingface.co/openai/privacy-filter/resolve/main/model.safetensors"),
    ]

    private var modelDir: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Masker/ai-model", isDirectory: true)
    }

    public init() {
        checkIfDownloaded()
    }

    public func checkIfDownloaded() {
        let fm = FileManager.default
        let safetensors = modelDir.appendingPathComponent("model.safetensors")
        isDownloaded = fm.fileExists(atPath: safetensors.path)
    }

    public func download() async {
        guard !isDownloading else { return }

        await MainActor.run {
            self.isDownloading = true
            self.progress = 0.0
            self.statusMessage = "准备下载 AI 模型 (2.6GB)..."
        }

        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        var allSuccess = true
        var completed: Int = 0

        for (name, urlStr) in files {
            guard let url = URL(string: urlStr) else { continue }

            await MainActor.run {
                self.statusMessage = "下载 \(name)..."
            }

            let success = await downloadFile(name: name, url: url)

            await MainActor.run {
                completed += 1
                self.progress = Double(completed) / Double(files.count)
            }

            if !success {
                allSuccess = false
                break
            }
        }

        await MainActor.run {
            self.isDownloading = false
            if allSuccess {
                self.isDownloaded = true
                self.statusMessage = "✅ AI 模型下载完成！请重启检测功能"
            } else {
                self.statusMessage = "❌ 下载失败，请检查网络后重试"
            }
        }
    }

    private func downloadFile(name: String, url: URL) async -> Bool {
        let dest = modelDir.appendingPathComponent(name)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("masker_\(name)")

        // Resume support: check if partial download exists
        var existingSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path) {
            existingSize = (attrs[.size] as? Int64) ?? 0
        }

        var request = URLRequest(url: url)
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
        }

        return await withCheckedContinuation { continuation in
            let session = URLSession(configuration: .default)
            let task = session.downloadTask(with: request) { tempURL, response, error in
                defer { session.invalidateAndCancel() }

                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                    continuation.resume(returning: false)
                    return
                }

                guard let tempURL = tempURL else {
                    continuation.resume(returning: false)
                    return
                }

                do {
                    if existingSize > 0 {
                        // Append to existing partial file
                        let fileHandle = try FileHandle(forWritingTo: tmp)
                        fileHandle.seekToEndOfFile()
                        let data = try Data(contentsOf: tempURL)
                        fileHandle.write(data)
                        try fileHandle.close()
                    } else {
                        try? FileManager.default.removeItem(at: tmp)
                        try FileManager.default.moveItem(at: tempURL, to: tmp)
                    }

                    // Move to final destination
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }

            // Observe progress
            let obs = task.progress.observe(\.fractionCompleted) { p, _ in
                DispatchQueue.main.async {
                    let fileProgress = p.fractionCompleted / Double(self.files.count)
                    let baseProgress = Double(self.files.count - 1) / Double(self.files.count)
                    self.progress = baseProgress + fileProgress
                }
            }
            task.resume()
            _ = obs
        }
    }

    public var modelPath: String {
        modelDir.path
    }
}
#endif
