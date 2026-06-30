#if !NO_AI
import Foundation

/// Downloads and manages the AI model from OpenList
public class ModelDownloader: ObservableObject {
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = ""
    @Published public var isDownloading: Bool = false
    @Published public var isDownloaded: Bool = false

    private let downloadURL = "http://lsyangyi.asuscomm.com:5245/d/ai-model.zip?sign=tnwYagbwV7zTECPsb5-gvjU14c4NIeTamQvdOw4dTgs=:0"

    private var modelDir: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Masker/ai-model", isDirectory: true)
    }

    private var zipPath: URL {
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("ai-model.zip")
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

        // Create directory
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Download with progress
        let result = await downloadWithProgress()

        if result {
            await MainActor.run {
                self.isDownloaded = true
                self.statusMessage = "✅ AI 模型下载完成！请重启检测功能"
            }
        } else {
            await MainActor.run {
                self.statusMessage = "❌ 下载失败，请检查网络后重试"
            }
        }

        await MainActor.run {
            self.isDownloading = false
        }
    }

    private func downloadWithProgress() async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let url = URL(string: self.downloadURL)!

                let session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)

                // Use a URLSessionDownloadTask for progress tracking
                let task = session.downloadTask(with: url) { [self] tempURL, response, error in
                    defer { session.invalidateAndCancel() }

                    guard let tempURL = tempURL, error == nil else {
                        continuation.resume(returning: false)
                        return
                    }

                    do {
                        // Move zip to tmp
                        try? FileManager.default.removeItem(at: self.zipPath)
                        try FileManager.default.moveItem(at: tempURL, to: self.zipPath)

                        // Extract
                        DispatchQueue.main.sync {
                            self.statusMessage = "正在解压..."
                        }

                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                        process.arguments = ["-o", self.zipPath.path, "-d", self.modelDir.path]

                        let pipe = Pipe()
                        process.standardOutput = pipe
                        process.standardError = pipe

                        try process.run()
                        process.waitUntilExit()

                        try? FileManager.default.removeItem(at: self.zipPath)

                        let success = process.terminationStatus == 0
                        continuation.resume(returning: success)

                    } catch {
                        continuation.resume(returning: false)
                    }
                }

                // Progress observer
                let observation = task.progress.observe(\.fractionCompleted) { [self] progress, _ in
                    DispatchQueue.main.sync {
                        self.progress = progress.fractionCompleted
                        let pct = Int(progress.fractionCompleted * 100)
                        self.statusMessage = "下载中... \(pct)%"
                    }
                }

                task.resume()

                // Keep observation alive
                _ = observation
            }
        }
    }

    public var modelPath: String {
        modelDir.path
    }
}
#endif
