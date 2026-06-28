import Foundation
import UniformTypeIdentifiers

/// Extracts text from various file formats using Python-based extractor
public class FileExtractor: ObservableObject {
    private let scriptPath: String
    private let pythonPath: String

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        scriptPath = "\(home)/projects/masker/extract_text.py"
        pythonPath = "\(home)/projects/masker/.venv/bin/python"
    }

    /// Check if file format is directly readable as plain text
    public func isPlainText(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercasingFirst
        let plainTypes: Set<String> = ["txt", "log", "json", "xml", "yaml", "yml", "csv", "md", "conf", "ini", "cfg"]
        return plainTypes.contains(ext)
    }

    /// Supported file types for extraction
    public var supportedUTTypes: [UTType] {
        [
            .plainText, .text, .log, .json, .xml, .yaml, .commaSeparatedText,
            .pdf,            // PDF
        ]
    }

    /// Try to read a file directly as plain text
    public func readPlainText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let str = String(data: data, encoding: .utf8) ??
                        String(data: data, encoding: .utf16) else {
            return nil
        }
        return str
    }

    /// Extract text from any supported file format using Python
    public func extract(_ url: URL) async -> String? {
        // First try plain text
        if isPlainText(url) {
            if let text = readPlainText(url) {
                return text
            }
        }

        // Use Python extractor for binary formats
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.pythonPath)
                process.arguments = [self.scriptPath, url.path]

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: outputData, encoding: .utf8), !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

extension String {
    var lowercasingFirst: String {
        guard !isEmpty else { return self }
        return prefix(1).lowercased() + dropFirst()
    }
}
