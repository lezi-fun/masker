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
        checkIfDownloaded()
        guard !isDownloaded else {
            await MainActor.run {
                self.statusMessage = "✅ AI 模型已就绪"
            }
            return
        }

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

        await MainActor.run {
            self.statusMessage = "下载 \(name)..."
        }

        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: url) { [self] tempURL, response, error in
            defer { session.invalidateAndCancel() }

            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                return
            }

            guard let tempURL = tempURL else { return }

            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)
            } catch {}
        }

        // Progress polling
        Task {
            while task.state == .running {
                let pct = task.progress.fractionCompleted
                await MainActor.run {
                    let base = Double(self.files.count - 1) / Double(self.files.count)
                    self.progress = base + pct / Double(self.files.count)
                    self.statusMessage = "下载 \(name)... \(Int(pct * 100))%"
                }
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            task.resume()
            // Wait for task completion via URLSession delegate queue
            Task {
                while task.state == .running {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                continuation.resume()
            }
        }

        return FileManager.default.fileExists(atPath: dest.path)
    }

    public var modelPath: String {
        modelDir.path
    }
}
#endif
