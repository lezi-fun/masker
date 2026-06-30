import Foundation
import UniformTypeIdentifiers

/// Extracts text from various file formats using macOS built-in tools + Python
public class FileExtractor: ObservableObject {
    private let scriptPath: String
    private let pythonPath: String

    public init() {
        let fm = FileManager.default
        // Check if running inside .app bundle
        if let bundlePath = Bundle.main.resourcePath {
            let bundledPython = "\(bundlePath)/.venv/bin/python"
            if fm.fileExists(atPath: bundledPython) {
                pythonPath = bundledPython
                scriptPath = "\(bundlePath)/extract_text.py"
            } else {
                // Dev mode fallback
                let home = fm.homeDirectoryForCurrentUser.path
                pythonPath = "\(home)/projects/masker/.venv/bin/python"
                scriptPath = "\(home)/projects/masker/extract_text.py"
            }
        } else {
            let home = fm.homeDirectoryForCurrentUser.path
            pythonPath = "\(home)/projects/masker/.venv/bin/python"
            scriptPath = "\(home)/projects/masker/extract_text.py"
        }
    }

    /// Check if file format is directly readable as plain text
    public func isPlainText(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let plainTypes: Set<String> = ["txt", "log", "json", "xml", "yaml", "yml", "csv", "md", "conf", "ini", "cfg"]
        return plainTypes.contains(ext)
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

    /// Extract text from any supported file format
    public func extract(_ url: URL) async -> String? {
        // First try plain text
        if isPlainText(url) {
            if let text = readPlainText(url) {
                return text
            }
        }

        let ext = url.pathExtension.lowercased()

        // DOCX: use macOS built-in textutil (always available, no Python needed)
        if ext == "docx" {
            return await extractWithTextutil(url)
        }

        // PDF / XLSX / others: use Python extractor
        return await extractWithPython(url)
    }

    /// Extract text from DOCX using macOS built-in textutil
    private func extractWithTextutil(_ url: URL) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
                process.arguments = ["-convert", "txt", "-stdout", url.path]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8), !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continuation.resume(returning: output)
                    } else {
                        // textutil failed, try Python fallback
                        Task { [self] in
                            let result = await self.extractWithPython(url)
                            continuation.resume(returning: result)
                        }
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Extract text using Python extract_text.py
    private func extractWithPython(_ url: URL) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let fm = FileManager.default
                guard fm.fileExists(atPath: self.pythonPath),
                      fm.fileExists(atPath: self.scriptPath) else {
                    continuation.resume(returning: nil)
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.pythonPath)
                process.arguments = [self.scriptPath, url.path]

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = Pipe()

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
