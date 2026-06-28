import Foundation

/// Thread-safe store that maps UUIDs ↔ original sensitive text
public class MappingStore: ObservableObject {
    @Published public private(set) var mappings: [(uuid: String, original: String, type: SensitiveType)] = []

    private let lock = NSLock()

    public init() {}

    /// Replace all detected sensitive segments with UUIDs.
    /// Returns (sanitizedText, newMappings)
    public func sanitize(_ text: String, segments: [SensitiveSegment], showType: Bool = true) -> (text: String, mappings: [(uuid: String, original: String, type: SensitiveType)]) {
        lock.lock()
        defer { lock.unlock() }

        let nsText = text as NSString
        // Sort segments descending by location so replacements don't shift indices
        let sorted = segments.sorted { $0.range.location > $1.range.location }
        var result = text
        var newMappings: [(uuid: String, original: String, type: SensitiveType)] = []

        for seg in sorted {
            let uuid = UUID().uuidString.prefix(8).uppercased()
            let typeTag = showType ? typeTag(for: seg.type) : ""
            let placeholder = "🔒\(uuid)\(typeTag)🔒"
            // Replace in NSString range
            let nsRange = seg.range
            if nsRange.location + nsRange.length <= nsText.length {
                result = (result as NSString).replacingCharacters(in: nsRange, with: placeholder)
                newMappings.append((uuid: String(uuid), original: seg.original, type: seg.type))
            }
        }

        // Prepend to existing mappings (newest first)
        self.mappings = newMappings + self.mappings

        return (result, newMappings)
    }

    /// Restore UUID placeholders back to original text
    public func restore(_ text: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        var result = text
        // Sort by UUID length descending to avoid partial replacement issues
        let sortedMappings = mappings.sorted { $0.uuid.count > $1.uuid.count }

        for mapping in sortedMappings {
            // Try with type tag first: 🔒UUID.类型🔒
            let typeTag = typeTag(for: mapping.type)
            let withType = "🔒\(mapping.uuid)\(typeTag)🔒"
            result = result.replacingOccurrences(of: withType, with: mapping.original)

            // Also try without type tag: 🔒UUID🔒
            let withoutType = "🔒\(mapping.uuid)🔒"
            result = result.replacingOccurrences(of: withoutType, with: mapping.original)

            // Last resort: bare UUID (AI might strip emoji/tags)
            result = result.replacingOccurrences(of: mapping.uuid, with: mapping.original)
        }

        return result
    }

    /// Get the type tag string for a sensitive type
    private func typeTag(for type: SensitiveType) -> String {
        switch type {
        case .name: return ".姓名"
        case .phone: return ".手机"
        case .idCard: return ".身份证"
        case .email: return ".邮箱"
        case .url: return ".链接"
        case .bankCard: return ".银行卡"
        case .ip: return ".IP"
        case .passport: return ".护照"
        case .address: return ".地址"
        case .date: return ".日期"
        case .key: return ".密钥"
        case .custom: return ".自定义"
        }
    }

    /// Export mapping as JSON
    public func exportJSON() -> String {
        lock.lock()
        defer { lock.unlock() }

        let dictArray = mappings.map { m -> [String: String] in
            ["uuid": m.uuid, "original": m.original, "type": m.type.rawValue]
        }
        if let data = try? JSONSerialization.data(withJSONObject: dictArray, options: [.prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

    /// Import mappings from JSON
    public func importJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        var imported: [(uuid: String, original: String, type: SensitiveType)] = []
        for item in array {
            guard let uuid = item["uuid"], let original = item["original"],
                  let typeStr = item["type"] else { continue }
            // Find matching type
            let type = SensitiveType.allCases.first { $0.rawValue == typeStr } ?? .phone
            imported.append((uuid: uuid, original: original, type: type))
        }

        // Merge: new imports prepended
        self.mappings = imported + self.mappings
        return true
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        mappings.removeAll()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return mappings.count
    }
}
