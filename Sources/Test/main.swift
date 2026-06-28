import Foundation
import MaskerCore

@main
struct FormatTest {
    static func main() async {
        let extractor = FileExtractor()
        let detector = SensitiveDetector()
        let store = MappingStore()

        let files = [
            "test_files/test.docx",
            "test_files/test.pdf",
            "test_files/test.xlsx",
            "test_files/test.txt",
        ]

        for file in files {
            let url = URL(fileURLWithPath: file)
            guard let text = await extractor.extract(url) else {
                print("❌ \(file): 无法提取文本")
                continue
            }

            let segments = detector.detect(in: text)
            let (sanitized, mappings) = store.sanitize(text, segments: segments, showType: true)
            let restored = store.restore(sanitized)
            let matched = text == restored

            let typeSummary = Dictionary(grouping: mappings, by: \.type)
                .map { "\($0.key.rawValue):\($0.value.count)" }
                .sorted().joined(separator: " ")

            print("""
            📄 \(file)
               文本: \(text.count) 字符
               敏感项: \(mappings.count) 项 [\(typeSummary)]
               还原: \(matched ? "✅" : "❌")
               脱敏样例: \(sanitized.prefix(80))...

            """)
        }
    }
}
