import Foundation

public enum SQLExtractor {
    private static let pattern = #"```sql\s*\n([\s\S]*?)```"#

    public static func extract(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            let sql = text[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
            return sql.isEmpty ? nil : sql
        }
    }

    public static func extractFirst(from text: String) -> String? {
        extract(from: text).first
    }
}
