import Foundation

public enum TranscriptRole: String, Codable, Sendable {
    case assistant
    case user
    case system
}

public enum TranscriptKind: Equatable, Sendable, Codable {
    case text
    case thinking
    case commandPreview(sql: String, sourceName: String)
    case rawCommandPreview(command: String)
    case commandResult(exitCode: Int32, stdout: String, stderr: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case sql
        case sourceName
        case command
        case exitCode
        case stdout
        case stderr
    }

    private enum KindType: String, Codable {
        case text
        case thinking
        case commandPreview
        case rawCommandPreview
        case commandResult
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)

        switch type {
        case .text:
            self = .text
        case .thinking:
            self = .thinking
        case .commandPreview:
            self = .commandPreview(
                sql: try container.decode(String.self, forKey: .sql),
                sourceName: try container.decode(String.self, forKey: .sourceName)
            )
        case .rawCommandPreview:
            self = .rawCommandPreview(
                command: try container.decode(String.self, forKey: .command)
            )
        case .commandResult:
            self = .commandResult(
                exitCode: try container.decode(Int32.self, forKey: .exitCode),
                stdout: try container.decode(String.self, forKey: .stdout),
                stderr: try container.decode(String.self, forKey: .stderr)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text:
            try container.encode(KindType.text, forKey: .type)
        case .thinking:
            try container.encode(KindType.thinking, forKey: .type)
        case let .commandPreview(sql, sourceName):
            try container.encode(KindType.commandPreview, forKey: .type)
            try container.encode(sql, forKey: .sql)
            try container.encode(sourceName, forKey: .sourceName)
        case let .rawCommandPreview(command):
            try container.encode(KindType.rawCommandPreview, forKey: .type)
            try container.encode(command, forKey: .command)
        case let .commandResult(exitCode, stdout, stderr):
            try container.encode(KindType.commandResult, forKey: .type)
            try container.encode(exitCode, forKey: .exitCode)
            try container.encode(stdout, forKey: .stdout)
            try container.encode(stderr, forKey: .stderr)
        }
    }
}

public struct TranscriptItem: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let role: TranscriptRole
    public let title: String
    public let body: String
    public let kind: TranscriptKind
    public let timestamp: Date
    public var isPinned: Bool
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        role: TranscriptRole,
        title: String,
        body: String,
        kind: TranscriptKind = .text,
        timestamp: Date = Date(),
        isPinned: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.body = body
        self.kind = kind
        self.timestamp = timestamp
        self.isPinned = isPinned
        self.tags = tags
    }
}

public enum TranscriptTiming {
    /// Calculate the time gap between each consecutive pair of items
    public static func itemDurations(in items: [TranscriptItem]) -> [(item: TranscriptItem, gapSeconds: TimeInterval)] {
        guard items.count >= 2 else {
            return items.map { ($0, 0) }
        }
        var result: [(TranscriptItem, TimeInterval)] = [( items[0], 0)]
        for i in 1..<items.count {
            let gap = items[i].timestamp.timeIntervalSince(items[i-1].timestamp)
            result.append((items[i], gap))
        }
        return result
    }

    /// Find the longest gap between consecutive items
    public static func longestGap(in items: [TranscriptItem]) -> TimeInterval {
        let durations = itemDurations(in: items)
        return durations.map(\.gapSeconds).max() ?? 0
    }
}

public enum TranscriptFilter {
    /// Filter transcript items by date range
    public static func items(in items: [TranscriptItem], from start: Date, to end: Date) -> [TranscriptItem] {
        items.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    /// Get items from the last N seconds
    public static func recentItems(in items: [TranscriptItem], seconds: TimeInterval) -> [TranscriptItem] {
        let cutoff = Date().addingTimeInterval(-seconds)
        return items.filter { $0.timestamp >= cutoff }
    }

    /// Get only error results
    public static func errorResults(in items: [TranscriptItem]) -> [TranscriptItem] {
        items.filter {
            if case let .commandResult(exitCode, _, _) = $0.kind { return exitCode != 0 }
            return false
        }
    }

    /// Get only successful results
    public static func successResults(in items: [TranscriptItem]) -> [TranscriptItem] {
        items.filter {
            if case let .commandResult(exitCode, _, _) = $0.kind { return exitCode == 0 }
            return false
        }
    }
}

public enum TranscriptAnalytics {
    /// Total word count across all transcript items
    public static func wordCount(in items: [TranscriptItem]) -> Int {
        items.reduce(0) { total, item in
            total + item.body.split(whereSeparator: \.isWhitespace).count
        }
    }

    /// Total character count across all transcript items
    public static func characterCount(in items: [TranscriptItem]) -> Int {
        items.reduce(0) { total, item in
            total + item.body.count
        }
    }

    /// Average words per message
    public static func averageWordsPerMessage(in items: [TranscriptItem]) -> Double {
        guard !items.isEmpty else { return 0 }
        return Double(wordCount(in: items)) / Double(items.count)
    }

    /// Time span of the transcript (first to last timestamp)
    public static func timeSpan(of items: [TranscriptItem]) -> TimeInterval {
        guard let first = items.first?.timestamp, let last = items.last?.timestamp else { return 0 }
        return last.timeIntervalSince(first)
    }
}

public enum MarkdownDetector {
    /// Detect if text contains SQL code blocks
    public static func containsSQLBlock(_ text: String) -> Bool {
        text.contains("```sql") || text.contains("```SQL")
    }

    /// Detect if text contains any fenced code blocks
    public static func containsCodeBlock(_ text: String) -> Bool {
        text.contains("```")
    }

    /// Extract the first code block content from markdown text
    public static func extractFirstCodeBlock(from text: String) -> String? {
        let pattern = "```(?:\\w+)?\\s*\\n([\\s\\S]*?)\\n\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let contentRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Count the number of code blocks in text
    public static func codeBlockCount(in text: String) -> Int {
        let pattern = "```(?:\\w+)?\\s*\\n[\\s\\S]*?\\n\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

public struct PromptChip: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let prompt: String

    public init(id: UUID = UUID(), title: String, prompt: String) {
        self.id = id
        self.title = title
        self.prompt = prompt
    }
}
