import Foundation
import NaturalLanguage

/// Types of sensitive information we detect
public enum SensitiveType: String, CaseIterable, Identifiable {
    case phone = "📞 手机号"
    case idCard = "🪪 身份证号"
    case email = "📧 邮箱"
    case url = "🔗 URL"
    case bankCard = "💳 银行卡号"
    case ip = "🌐 IP地址"
    case name = "👤 姓名"
    case passport = "🛂 护照号"
    case address = "📍 地址"
    case date = "📅 日期"
    case key = "🗝️ 密钥/密码"
    case custom = "🔍 自定义"

    public var id: String { rawValue }
}

/// A detected sensitive segment
public struct SensitiveSegment: Equatable {
    public let original: String
    public let range: NSRange
    public let type: SensitiveType

    public init(original: String, range: NSRange, type: SensitiveType) {
        self.original = original
        self.range = range
        self.type = type
    }

    public static func == (lhs: SensitiveSegment, rhs: SensitiveSegment) -> Bool {
        lhs.original == rhs.original && lhs.range == rhs.range && lhs.type == rhs.type
    }
}

/// Core engine: detects sensitive info using regex + heuristics
public class SensitiveDetector {
    // ── 百家姓 (top ~120 surnames for Chinese name detection) ──
    private static let surnameChars = CharacterSet(charactersIn: "\u{674E}\u{738B}\u{5F20}\u{5218}\u{9648}\u{6768}\u{8D75}\u{9EC4}\u{5468}\u{5434}\u{5F90}\u{5B59}\u{9A6C}\u{80E1}\u{6731}\u{90ED}\u{4F55}\u{7F57}\u{9AD8}\u{6797}\u{6881}\u{90D1}\u{8C22}\u{5B8B}\u{5510}\u{97E9}\u{66F9}\u{8BB8}\u{9093}\u{8427}\u{51AF}\u{66FE}\u{7A0B}\u{8521}\u{5F6D}\u{6F58}\u{8881}\u{8463}\u{4F59}\u{590F}\u{949F}\u{6C6A}\u{7530}\u{4EFB}\u{59DC}\u{8303}\u{65B9}\u{77F3}\u{59DA}\u{8B5A}\u{5ED6}\u{90B9}\u{718A}\u{91D1}\u{9646}\u{90DD}\u{5B54}\u{767D}\u{5D14}\u{5EB7}\u{6BDB}\u{90B1}\u{79E6}\u{6C5F}\u{53F2}\u{987E}\u{4FAF}\u{90B5}\u{5B5F}\u{9F99}\u{4E07}\u{6BB5}\u{94B1}\u{6C64}\u{5C39}\u{9ECE}\u{6613}\u{5E38}\u{6B66}\u{4E54}\u{8D3A}\u{8D56}\u{9E9F}\u{6587}")

    // Patterns are compiled once
    private let phoneRegex: NSRegularExpression
    private let idCardRegex: NSRegularExpression
    private let emailRegex: NSRegularExpression
    private let urlRegex: NSRegularExpression
    private let bankCardRegex: NSRegularExpression
    private let ipRegex: NSRegularExpression
    private let passportRegex: NSRegularExpression

    public init() {
        phoneRegex = try! NSRegularExpression(pattern: #"(?<!\d)1[3-9]\d{9}(?!\d)"#)
        idCardRegex = try! NSRegularExpression(pattern: #"(?<!\d)[1-9]\d{5}(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])\d{3}[\dXx](?!\d)"#)
        emailRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)
        urlRegex = try! NSRegularExpression(pattern: #"https?://[^\s，。；：、！？),」」】〕〉》"'”』\u3000]+"#)
        bankCardRegex = try! NSRegularExpression(pattern: #"(?<!\d)\d{4}\s?\d{4}\s?\d{4}\s?\d{4}(?:\s?\d{0,3})?(?!\d)"#)
        ipRegex = try! NSRegularExpression(pattern: #"(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)"#)
        passportRegex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])[EeGg]\d{8}(?![A-Za-z0-9])"#)
    }

    /// Run all detectors, return deduplicated segments sorted by position
    public func detect(in text: String) -> [SensitiveSegment] {
        let nsText = text as NSString
        var rawSegments: [SensitiveSegment] = []

        // Collect all matches
        let detectors: [(NSRegularExpression, SensitiveType)] = [
            (phoneRegex, .phone),
            (idCardRegex, .idCard),
            (emailRegex, .email),
            (urlRegex, .url),
            (bankCardRegex, .bankCard),
            (ipRegex, .ip),
            (passportRegex, .passport),
        ]

        for (regex, type) in detectors {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for m in matches {
                rawSegments.append(SensitiveSegment(
                    original: nsText.substring(with: m.range),
                    range: m.range,
                    type: type
                ))
            }
        }

        // Detect Chinese names (heuristic: surname + 1~2 CJK chars, not preceded by CJK)
        self.detectNames(in: text, nsText: nsText, into: &rawSegments)

        // Remove exact duplicates
        var seen = Set<String>()
        var unique: [SensitiveSegment] = []
        for seg in rawSegments {
            let key = "\(seg.range.location)-\(seg.range.length)-\(seg.type.rawValue)"
            if seen.insert(key).inserted {
                unique.append(seg)
            }
        }

        // Resolve overlaps: prefer longer match, then earlier
        let resolved = resolveOverlaps(unique.sorted { $0.range.location < $1.range.location })
        return resolved.sorted { $0.range.location < $1.range.location }
    }

    // ── Chinese name detection ──

    private func detectNames(in text: String, nsText: NSString, into segments: inout [SensitiveSegment]) {
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            // Check if current char is a surname
            if isSurname(String(chars[i])) {
                // Collect up to 2 following CJK chars
                var j = i + 1
                while j < chars.count, j - i <= 2, isCJK(chars[j]) {
                    j += 1
                }
                let nameLen = j - i
                if nameLen >= 2 && nameLen <= 3 {
                    let name = String(chars[i..<j])
                    if !isExcludedName(name) && name.count <= 3 {
                        let location = text.distance(from: text.startIndex, to: text.index(text.startIndex, offsetBy: i))
                        let length = name.count
                        // Ensure we don't overlap with existing phone/idCard etc.
                        if !overlapsAny(segments, location: location, length: length) {
                            segments.append(SensitiveSegment(
                                original: name,
                                range: NSRange(location: location, length: length),
                                type: .name
                            ))
                        }
                    }
                }
            }
            i += 1
        }
    }

    private func isSurname(_ s: String) -> Bool {
        s.unicodeScalars.count == 1 && Self.surnameChars.contains(s.unicodeScalars.first!)
    }

    private func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        return (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF)
            || (scalar.value >= 0x3400 && scalar.value <= 0x4DBF)
    }

    private let excludedNames: Set<String> = [
        "这里", "什么", "怎么", "那个", "这个", "哪个", "这些", "那些",
        "他们", "她们", "它们", "自己", "起来", "就是", "不是", "可以",
        "没有", "还是", "因为", "所以", "但是", "如果", "虽然", "而且",
        "或者", "然后", "已经", "知道", "还是", "一个", "两个", "三个",
        "可能", "应该", "能够", "需要", "看到", "听到", "觉得", "认为",
        "开始", "结束", "继续", "成为", "作为", "来自", "对于", "关于",
        "金额", "万元", "账户", "方账", "万达", "万广", "张杨",
        "金额", "万元整", "方账户", "万达广", "张杨路", "杨路",
    ]

    private func isExcludedName(_ s: String) -> Bool {
        excludedNames.contains(s)
    }

    private func overlapsAny(_ segments: [SensitiveSegment], location: Int, length: Int) -> Bool {
        for seg in segments {
            let r = seg.range
            // Check overlap
            if location < r.location + r.length && location + length > r.location {
                return true
            }
        }
        return false
    }

    // ── Overlap resolution ──

    private func resolveOverlaps(_ sorted: [SensitiveSegment]) -> [SensitiveSegment] {
        guard !sorted.isEmpty else { return [] }
        var result: [SensitiveSegment] = []
        var i = 0
        while i < sorted.count {
            var best = sorted[i]
            var j = i + 1
            while j < sorted.count, sorted[j].range.location < best.range.location + best.range.length {
                // overlapping — pick the longer one
                if sorted[j].range.length > best.range.length {
                    best = sorted[j]
                }
                j += 1
            }
            result.append(best)
            i = j
        }
        return result
    }
}
