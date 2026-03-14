import Foundation
import AppKit
import DuckDBAdapter
import SiftCore

@MainActor
public protocol CommandExecuting: Sendable {
    func execute(plan: DuckDBCommandPlan) async throws -> DuckDBExecutionResult
    func executeRaw(argumentsLine: String) async throws -> DuckDBExecutionResult
}

extension DuckDBCLIExecutor: CommandExecuting {}

public enum SidebarDestination: String, CaseIterable, Hashable, Identifiable, Codable {
    case assistant = "Assistant"
    case transcripts = "Transcripts"
    case setup = "Setup"
    case settings = "Settings"

    public var id: String { rawValue }
}

@MainActor
public final class SiftViewModel: ObservableObject {
    @Published public var selectedDestination: SidebarDestination? = .assistant
    @Published public var composerText = ""
    @Published public private(set) var transcript: [TranscriptItem]
    @Published public private(set) var sources: [DataSource]
    @Published public private(set) var selectedSource: DataSource?
    @Published public private(set) var lastExecution: DuckDBExecutionResult?
    @Published public private(set) var executionHistory: [QueryExecutionStats] = []
    @Published public private(set) var providerStatuses: [ProviderStatus]
    @Published public private(set) var settings: AppSettings
    @Published public var manualDuckDBArguments = ""
    @Published public var composerFocusRequestID = 0
    @Published public var isDiagnosticsDrawerPresented = false
    @Published public var isSetupFlowPresented = false
    @Published public private(set) var isRunning = false
    @Published public private(set) var isCancelled = false
    @Published public var searchQuery = ""
    @Published public private(set) var searchResults: [TranscriptItem] = []

    private var runningTask: Task<Void, Never>?

    private let executor: (any CommandExecuting)?
    private let chatResponder: any ProviderResponding
    private let sessionStore: any AppSessionPersisting
    private let secretStore: any ProviderSecretStoring
    private let environment: [String: String]

    public init(
        executor: (any CommandExecuting)? = try? DuckDBCLIExecutor(),
        chatResponder: any ProviderResponding = ProviderChatService(),
        sessionStore: any AppSessionPersisting = AppSessionStore(),
        secretStore: any ProviderSecretStoring = KeychainStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executor = executor
        self.chatResponder = chatResponder
        self.sessionStore = sessionStore
        self.secretStore = secretStore
        self.environment = environment

        let snapshot = sessionStore.loadSnapshot()
        self.settings = snapshot?.settings ?? AppSettings()
        self.sources = snapshot?.sources ?? []
        self.transcript = snapshot?.transcript.isEmpty == false ? snapshot!.transcript : Self.initialTranscript
        if let selectedSourceID = snapshot?.selectedSourceID {
            self.selectedSource = snapshot?.sources.first(where: { $0.id == selectedSourceID })
        } else {
            self.selectedSource = nil
        }
        self.providerStatuses = ProviderDiagnostics.detect(
            environment: environment,
            secretStore: secretStore
        )
        self.selectedDestination = settings.hasCompletedSetup ? .assistant : .setup
        self.isSetupFlowPresented = !settings.hasCompletedSetup
    }

    public static var initialTranscript: [TranscriptItem] {
        [
            TranscriptItem(
                role: .assistant,
                title: "Assistant",
                body: "Welcome. Finish setup, open a `.duckdb` or `.parquet` source, then ask for SQL or use the selected provider for broader analysis."
            ),
        ]
    }

    public var promptChips: [PromptChip] {
        PromptLibrary.prompts(for: selectedSource)
    }

    public var requiresInitialSetup: Bool {
        !settings.hasCompletedSetup
    }

    public var selectedProvider: ProviderKind {
        settings.defaultProvider
    }

    public var metalSnapshot: MetalWorkspaceSnapshot {
        let destination: MetalWorkspaceDestination
        switch selectedDestination ?? .assistant {
        case .assistant:
            destination = .assistant
        case .transcripts:
            destination = .transcripts
        case .setup:
            destination = .setup
        case .settings:
            destination = .settings
        }

        let executionState: MetalExecutionState
        if let lastExecution {
            executionState = lastExecution.exitCode == 0 ? .success : .failure
        } else {
            executionState = .idle
        }

        let commandDurationMilliseconds: Double
        let commandOutputBytes: Int
        if let lastExecution {
            commandDurationMilliseconds = max(
                0,
                lastExecution.endedAt.timeIntervalSince(lastExecution.startedAt) * 1000
            )
            commandOutputBytes = lastExecution.stdout.utf8.count + lastExecution.stderr.utf8.count
        } else {
            commandDurationMilliseconds = 0
            commandOutputBytes = 0
        }

        let providerReadiness = providerStatuses.reduce(into: 0) { count, status in
            if status.cliInstalled || status.apiKeyPresent || status.environmentKeyPresent {
                count += 1
            }
        }

        return MetalWorkspaceSnapshot(
            destination: destination,
            provider: selectedProvider,
            sourceKind: selectedSource?.kind,
            sourceCount: sources.count,
            transcriptCount: transcript.count,
            providerReadiness: providerReadiness,
            executionState: executionState,
            commandDurationMilliseconds: commandDurationMilliseconds,
            commandOutputBytes: commandOutputBytes,
            isRunning: isRunning
        )
    }

    public func preference(for provider: ProviderKind) -> ProviderPreference {
        settings.preference(for: provider)
    }

    public func status(for provider: ProviderKind) -> ProviderStatus? {
        providerStatuses.first(where: { $0.provider == provider })
    }

    /// Returns tab-completion suggestions for the current composer text
    public var commandCompletions: [CommandInfo] {
        CommandRegistry.completions(for: composerText)
    }

    /// Sources that no longer exist on disk
    public var missingSources: [DataSource] {
        sources.filter { !$0.fileExists }
    }

    /// Validate all sources and remove missing ones
    public func removeMissingSources() -> Int {
        let missing = missingSources
        guard !missing.isEmpty else { return 0 }

        for source in missing {
            sources.removeAll(where: { $0.id == source.id })
        }
        if let selectedSource, !sources.contains(where: { $0.id == selectedSource.id }) {
            self.selectedSource = sources.first
        }

        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Sources Cleaned",
                body: "Removed \(missing.count) source\(missing.count == 1 ? "" : "s") that no longer exist on disk."
            )
        )
        persistSnapshot()
        return missing.count
    }

    /// Pinned transcript items
    public var pinnedItems: [TranscriptItem] {
        transcript.filter(\.isPinned)
    }

    /// Toggle pin state for a transcript item
    public func togglePin(for itemID: UUID) {
        guard let index = transcript.firstIndex(where: { $0.id == itemID }) else { return }
        transcript[index].isPinned.toggle()
        persistSnapshot()
    }

    /// Add a tag to a transcript item
    public func addTag(_ tag: String, to itemID: UUID) {
        guard let index = transcript.firstIndex(where: { $0.id == itemID }) else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !transcript[index].tags.contains(trimmed) else { return }
        transcript[index].tags.append(trimmed)
        persistSnapshot()
    }

    /// Remove a tag from a transcript item
    public func removeTag(_ tag: String, from itemID: UUID) {
        guard let index = transcript.firstIndex(where: { $0.id == itemID }) else { return }
        transcript[index].tags.removeAll(where: { $0 == tag })
        persistSnapshot()
    }

    /// Find transcript items with a specific tag
    public func transcriptItems(withTag tag: String) -> [TranscriptItem] {
        transcript.filter { $0.tags.contains(tag) }
    }

    /// All unique tags used across the transcript
    public var allTags: [String] {
        Array(Set(transcript.flatMap(\.tags))).sorted()
    }

    /// Toggle favorite status for a source
    public func toggleFavorite(for sourceID: UUID) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[index].isFavorite.toggle()
        persistSnapshot()
    }

    /// Favorite sources
    public var favoriteSources: [DataSource] {
        sources.filter(\.isFavorite)
    }

    /// Compare two sources
    public func compareSources(_ source1ID: UUID, _ source2ID: UUID) -> SourceComparison? {
        guard let s1 = sources.first(where: { $0.id == source1ID }),
              let s2 = sources.first(where: { $0.id == source2ID }) else {
            return nil
        }
        return SourceComparison(source1: s1, source2: s2)
    }

    /// Set an alias for a source
    public func setSourceAlias(_ alias: String?, for sourceID: UUID) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[index].alias = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        persistSnapshot()
    }

    /// Find sources by kind
    public func sources(ofKind kind: DataSourceKind) -> [DataSource] {
        sources.filter { $0.kind == kind }
    }

    /// Check if there are any command errors in the transcript
    public var hasCommandErrors: Bool {
        transcript.contains {
            if case let .commandResult(exitCode, _, _) = $0.kind { return exitCode != 0 }
            return false
        }
    }

    /// Get the last N transcript items
    public func lastTranscriptItems(_ count: Int) -> [TranscriptItem] {
        Array(transcript.suffix(max(0, count)))
    }

    /// Compact transcript — only user messages and command results
    public var compactTranscript: [TranscriptItem] {
        transcript.filter { item in
            item.role == .user ||
            (item.role == .assistant && {
                if case .commandResult = item.kind { return true }
                return false
            }())
        }
    }

    /// Record an execution for timing stats
    public func recordExecution(_ result: DuckDBExecutionResult) {
        let duration = result.endedAt.timeIntervalSince(result.startedAt) * 1000
        let stats = QueryExecutionStats(
            sql: result.sql,
            durationMilliseconds: duration,
            succeeded: result.exitCode == 0
        )
        executionHistory.append(stats)
    }

    /// Average query execution time in milliseconds
    public var averageExecutionTimeMs: Double {
        guard !executionHistory.isEmpty else { return 0 }
        return executionHistory.reduce(0) { $0 + $1.durationMilliseconds } / Double(executionHistory.count)
    }

    /// Fastest query execution in the history
    public var fastestExecutionMs: Double? {
        executionHistory.map(\.durationMilliseconds).min()
    }

    /// Success rate of executed queries (0.0 to 1.0)
    public var executionSuccessRate: Double {
        guard !executionHistory.isEmpty else { return 0 }
        let successes = executionHistory.filter(\.succeeded).count
        return Double(successes) / Double(executionHistory.count)
    }

    /// Transcript analytics
    public var transcriptWordCount: Int {
        TranscriptAnalytics.wordCount(in: transcript)
    }

    /// Sources that are tabular files (not databases)
    public var tabularSources: [DataSource] {
        sources.filter(\.isTabularFile)
    }

    /// Sources that are databases
    public var databaseSources: [DataSource] {
        sources.filter { $0.kind == .duckdb }
    }

    /// Whether the composer text starts with a slash command prefix
    public var isComposerCommand: Bool {
        composerText.trimmingCharacters(in: .whitespaces).hasPrefix("/")
    }

    /// Number of pinned items in the transcript
    public var pinnedItemCount: Int {
        pinnedItems.count
    }

    /// Total tags used across all transcript items
    public var totalTagCount: Int {
        transcript.reduce(0) { $0 + $1.tags.count }
    }

    public var transcriptCharacterCount: Int {
        TranscriptAnalytics.characterCount(in: transcript)
    }

    /// Error results in the transcript
    public var errorResults: [TranscriptItem] {
        TranscriptFilter.errorResults(in: transcript)
    }

    /// Successful results in the transcript
    public var successResults: [TranscriptItem] {
        TranscriptFilter.successResults(in: transcript)
    }

    /// Number of favorite sources
    public var favoriteCount: Int {
        favoriteSources.count
    }

    /// Whether any source has an alias
    public var hasAliasedSources: Bool {
        sources.contains { $0.alias != nil }
    }

    /// Sources grouped by directory
    public var sourcesByDirectory: [String: [DataSource]] {
        Dictionary(grouping: sources, by: \.directoryName)
    }

    /// Import a source from a remote URL string
    public func importRemoteSource(urlString: String) {
        guard let source = DataSource.fromRemoteURL(urlString) else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Invalid URL",
                    body: "Could not import from `\(urlString)`. Only http/https URLs for supported file types are allowed."
                )
            )
            return
        }

        if sources.first(where: { $0.url == source.url }) == nil {
            sources.insert(source, at: 0)
            selectedSource = source
        } else {
            selectedSource = sources.first(where: { $0.url == source.url })
        }
        selectedDestination = .assistant
        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Remote Source",
                body: "Attached remote source `\(source.displayName)` from \(urlString)."
            )
        )
        persistSnapshot()
    }

    /// Smart prompt suggestions based on current context
    public var contextualSuggestions: [String] {
        var suggestions: [String] = []

        if sources.isEmpty {
            suggestions.append("Open a data file to get started")
            return suggestions
        }

        if commandCount == 0 {
            if let source = selectedSource {
                switch source.kind {
                case .parquet, .csv, .json:
                    suggestions.append("Preview rows")
                    suggestions.append("Show schema")
                    suggestions.append("Count rows")
                case .duckdb:
                    suggestions.append("Show tables")
                    suggestions.append("Database info")
                }
            }
            return suggestions
        }

        // After some commands have been run
        if let source = selectedSource, source.kind == .duckdb {
            suggestions.append("Show columns")
            if commandCount < 5 {
                suggestions.append("Summarize data")
            }
        }

        if executionHistory.contains(where: { !$0.succeeded }) {
            suggestions.append("Check the error and try a different query")
        }

        return suggestions
    }

    /// Cancel the currently running command
    public func cancelRunningCommand() {
        guard isRunning else { return }
        runningTask?.cancel()
        isCancelled = true
        isRunning = false
        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Cancelled",
                body: "The running command was cancelled."
            )
        )
    }

    public func importSource(url: URL) {
        guard let source = DataSource.from(url: url) else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Unsupported Source",
                    body: "Only `.duckdb`, `.db`, `.parquet`, `.csv`, `.tsv`, `.json`, `.jsonl`, and `.ndjson` files are supported."
                )
            )
            return
        }

        if let existing = sources.first(where: { $0.url == source.url }) {
            selectedSource = existing
        } else {
            sources.insert(source, at: 0)
            selectedSource = source
        }
        selectedDestination = .assistant

        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Source Attached",
                body: "Attached `\(source.displayName)` as the active data source."
            )
        )
        persistSnapshot()
    }

    @MainActor
    public func promptForSourceImport() {
        guard let url = SourcePicker.pickURL() else {
            return
        }
        importSource(url: url)
    }

    public func importSources(urls: [URL]) -> Int {
        var imported = 0
        for url in urls {
            guard let source = DataSource.from(url: url) else { continue }
            if sources.first(where: { $0.url == source.url }) == nil {
                sources.insert(source, at: 0)
                imported += 1
            }
        }
        if imported > 0 {
            selectedSource = sources.first
            selectedDestination = .assistant
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Sources Imported",
                    body: "Imported \(imported) new source\(imported == 1 ? "" : "s")."
                )
            )
            persistSnapshot()
        }
        return imported
    }

    public func selectSource(_ source: DataSource) {
        selectedSource = source
        selectedDestination = .assistant
        persistSnapshot()
    }

    public func removeSource(_ source: DataSource) {
        sources.removeAll(where: { $0.id == source.id })
        if selectedSource == source {
            selectedSource = sources.first
        }
        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Source Removed",
                body: "Removed `\(source.displayName)` from the workspace."
            )
        )
        persistSnapshot()
    }

    public func removeAllSources() {
        let count = sources.count
        sources.removeAll()
        selectedSource = nil
        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Sources Cleared",
                body: "Removed \(count) source\(count == 1 ? "" : "s") from the workspace."
            )
        )
        persistSnapshot()
    }

    public func triggerPrompt(_ prompt: String) async {
        composerText = prompt
        await sendPrompt()
    }

    public func sendPrompt() async {
        let prompt = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        isCancelled = false
        composerText = ""
        appendTranscript(
            TranscriptItem(
                role: .user,
                title: "You",
                body: prompt
            )
        )

        // Show thinking indicator immediately
        let thinkingItem = TranscriptItem(
            role: .assistant,
            title: "Assistant",
            body: "Thinking…",
            kind: .thinking
        )
        appendTranscript(thinkingItem)

        let action = AssistantPlanner.plan(prompt: prompt, source: selectedSource)
        switch action {
        case let .assistantReply(reply):
            replaceThinkingItem(thinkingItem.id, with:
                TranscriptItem(
                    role: .assistant,
                    title: "Assistant",
                    body: reply
                )
            )

        case let .command(plan):
            replaceThinkingItem(thinkingItem.id, with:
                TranscriptItem(
                    role: .assistant,
                    title: "Command Preview",
                    body: plan.explanation,
                    kind: .commandPreview(sql: plan.sql, sourceName: plan.source.displayName)
                )
            )

            guard let executor else {
                appendTranscript(
                    TranscriptItem(
                        role: .system,
                        title: "DuckDB Unavailable",
                        body: "The app could not locate the `duckdb` binary. Install DuckDB or set DUCKDB_BINARY."
                    )
                )
                return
            }

            isRunning = true
            isDiagnosticsDrawerPresented = true
            defer { isRunning = false }

            do {
                let result = try await executor.execute(plan: plan)
                lastExecution = result
                appendTranscript(
                    TranscriptItem(
                        role: .assistant,
                        title: result.exitCode == 0 ? "Command Result" : "Command Error",
                        body: result.exitCode == 0 ? "DuckDB finished running the command." : "DuckDB returned a non-zero exit code.",
                        kind: .commandResult(
                            exitCode: result.exitCode,
                            stdout: result.stdout,
                            stderr: result.stderr
                        )
                    )
                )
            } catch {
                appendTranscript(
                    TranscriptItem(
                        role: .system,
                        title: "Execution Failed",
                        body: error.localizedDescription
                    )
                )
            }

        case let .providerPrompt(providerPrompt):
            await sendProviderPrompt(providerPrompt, thinkingID: thinkingItem.id)

        case let .naturalLanguageQuery(nlPrompt, source):
            await executeNaturalLanguageQuery(prompt: nlPrompt, source: source, thinkingID: thinkingItem.id)

        case let .rawCommand(argumentsLine):
            removeThinkingItem(thinkingItem.id)
            await executeRawDuckDB(argumentsLine: argumentsLine, source: .chatComposer)

        case .clearConversation:
            removeThinkingItem(thinkingItem.id)
            clearConversation()

        case .listSources:
            let sourceList: String
            if sources.isEmpty {
                sourceList = "No sources attached. Use the toolbar to open a `.duckdb`, `.parquet`, or `.csv` file."
            } else {
                let lines = sources.enumerated().map { index, source in
                    let marker = source == selectedSource ? "→" : " "
                    return "\(marker) \(index + 1). **\(source.displayName)** (\(source.kind.rawValue))"
                }
                sourceList = "**Attached Sources**\n\n" + lines.joined(separator: "\n")
            }
            replaceThinkingItem(thinkingItem.id, with:
                TranscriptItem(
                    role: .assistant,
                    title: "Sources",
                    body: sourceList
                )
            )

        case .copyLastResult:
            removeThinkingItem(thinkingItem.id)
            copyLastResultToClipboard()

        case .exportTranscript:
            removeThinkingItem(thinkingItem.id)
            exportTranscriptToClipboard()

        case .showCommandCount:
            let stats = [
                "**Session Statistics**",
                "",
                "• Messages: \(transcript.count)",
                "• User messages: \(userMessageCount)",
                "• System messages: \(systemMessageCount)",
                "• Commands executed: \(commandCount)",
                "• Sources: \(sources.count)",
                "• Bookmarks: \(settings.bookmarks.count)",
            ]
            replaceThinkingItem(thinkingItem.id, with:
                TranscriptItem(
                    role: .assistant,
                    title: "Session Stats",
                    body: stats.joined(separator: "\n")
                )
            )

        case .showPinnedItems:
            let pinned = pinnedItems
            let body: String
            if pinned.isEmpty {
                body = "No pinned items. Pin a transcript item to save it for quick reference."
            } else {
                let lines = pinned.map { "📌 **\($0.title)**: \($0.body.prefix(100))\($0.body.count > 100 ? "..." : "")" }
                body = "**Pinned Items** (\(pinned.count))\n\n" + lines.joined(separator: "\n\n")
            }
            replaceThinkingItem(thinkingItem.id, with:
                TranscriptItem(
                    role: .assistant,
                    title: "Pinned",
                    body: body
                )
            )

        case .showTags:
            let tags = allTags
            let body: String
            if tags.isEmpty {
                body = "No tags in use. Add tags to transcript items to organize them."
            } else {
                let tagCounts = tags.map { tag in
                    let count = transcriptItems(withTag: tag).count
                    return "• **\(tag)** (\(count) item\(count == 1 ? "" : "s"))"
                }
                body = "**All Tags** (\(tags.count))\n\n" + tagCounts.joined(separator: "\n")
            }
            replaceThinkingItem(thinkingItem.id, with:
                TranscriptItem(
                    role: .assistant,
                    title: "Tags",
                    body: body
                )
            )

        case .resetWorkspace:
            removeThinkingItem(thinkingItem.id)
            resetWorkspace()

        case .showSourceInfo:
            if let source = selectedSource {
                let lines = [
                    "**Source Info**",
                    "",
                    "• Name: \(source.displayName)",
                    "• Type: \(source.kind.displayLabel)",
                    "• Path: `\(source.path)`",
                    "• Size: \(source.fileSizeDescription)",
                    "• Added: \(source.addedAt.formatted())",
                ]
                replaceThinkingItem(thinkingItem.id, with:
                    TranscriptItem(
                        role: .assistant,
                        title: "Source Info",
                        body: lines.joined(separator: "\n")
                    )
                )
            } else {
                replaceThinkingItem(thinkingItem.id, with:
                    TranscriptItem(
                        role: .assistant,
                        title: "No Source",
                        body: "No active source selected. Import a file first."
                    )
                )
            }

        case .undoLastMessage:
            removeThinkingItem(thinkingItem.id)
            undoLastUserMessage()

        case .bookmarkLastCommand:
            removeThinkingItem(thinkingItem.id)
            bookmarkLastCommand()

        case .showBookmarks:
            let bookmarks = settings.bookmarks
            let body: String
            if bookmarks.isEmpty {
                body = "No bookmarks saved. Run a command and use `/bookmark` to save it."
            } else {
                let lines = bookmarks.enumerated().map { index, bm in
                    "\(index + 1). `\(bm.sql)` → \(bm.sourceName)"
                }
                body = "**Saved Bookmarks** (\(bookmarks.count))\n\n" + lines.joined(separator: "\n")
            }
            replaceThinkingItem(thinkingItem.id, with:
                TranscriptItem(
                    role: .assistant,
                    title: "Bookmarks",
                    body: body
                )
            )

        case .showVersion:
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            replaceThinkingItem(thinkingItem.id, with:
                TranscriptItem(
                    role: .assistant,
                    title: "Version",
                    body: "**Sift** v\(version) (build \(build))\n\nA chat-first native macOS shell for exploring parquet and DuckDB files."
                )
            )

        case .showStatus:
            let statusLines = [
                "**Workspace Status**",
                "",
                "• Sources: \(sources.count)",
                "• Active source: \(selectedSource?.displayName ?? "none")",
                "• Provider: \(settings.defaultProvider.displayName)",
                "• Transcript items: \(transcript.count)",
                "• Commands run: \(transcript.filter { if case .commandResult = $0.kind { return true }; return false }.count)",
                "• Last execution: \(lastExecution != nil ? (lastExecution!.exitCode == 0 ? "✓ success" : "✗ failure") : "none")",
            ]
            replaceThinkingItem(thinkingItem.id, with:
                TranscriptItem(
                    role: .assistant,
                    title: "Status",
                    body: statusLines.joined(separator: "\n")
                )
            )

        case .showHistory:
            let commands = transcript.compactMap { item -> String? in
                switch item.kind {
                case let .commandPreview(sql, sourceName):
                    return "• `\(sql)` → \(sourceName)"
                case let .rawCommandPreview(command):
                    return "• `/duckdb \(command)`"
                default:
                    return nil
                }
            }
            let historyText: String
            if commands.isEmpty {
                historyText = "No commands in history. Run a query first."
            } else {
                let recent = commands.suffix(10)
                historyText = "**Recent Commands** (\(commands.count) total)\n\n" + recent.joined(separator: "\n")
            }
            replaceThinkingItem(thinkingItem.id, with:
                TranscriptItem(
                    role: .assistant,
                    title: "History",
                    body: historyText
                )
            )

        case let .rerunCommand(index):
            removeThinkingItem(thinkingItem.id)
            await rerunCommand(at: index)
        }
    }

    public func completeSetup(
        defaultProvider: ProviderKind,
        authMode: ProviderAuthMode,
        model: String,
        apiKey: String
    ) {
        settings.defaultProvider = defaultProvider
        settings.hasCompletedSetup = true
        settings.setPreference(
            ProviderPreference(authMode: authMode, customModel: model),
            for: defaultProvider
        )

        if authMode == .apiKey {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try? secretStore.saveAPIKey(trimmed, for: defaultProvider)
            }
        }

        refreshProviderStatuses()
        isSetupFlowPresented = false
        selectedDestination = .assistant
        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Setup Complete",
                body: "\(defaultProvider.displayName) is now the default provider. You can change this anytime in Settings."
            )
        )
        persistSnapshot()
    }

    public func reopenSetup() {
        isSetupFlowPresented = true
        selectedDestination = .setup
    }

    public func updateDefaultProvider(_ provider: ProviderKind) {
        settings.defaultProvider = provider
        if settings.providerPreferences[provider.rawValue] == nil {
            settings.setPreference(.default(for: provider), for: provider)
        }
        refreshProviderStatuses()
        persistSnapshot()
    }

    public func updateAuthMode(_ mode: ProviderAuthMode, for provider: ProviderKind) {
        var preference = settings.preference(for: provider)
        preference.authMode = mode
        settings.setPreference(preference, for: provider)
        refreshProviderStatuses()
        persistSnapshot()
    }

    public func updateCustomModel(_ model: String, for provider: ProviderKind) {
        var preference = settings.preference(for: provider)
        preference.customModel = model
        settings.setPreference(preference, for: provider)
        persistSnapshot()
    }

    public func saveAPIKey(_ key: String, for provider: ProviderKind) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? secretStore.saveAPIKey(trimmed, for: provider)
        refreshProviderStatuses()
        persistSnapshot()
    }

    public func removeAPIKey(for provider: ProviderKind) {
        try? secretStore.removeAPIKey(for: provider)
        refreshProviderStatuses()
        persistSnapshot()
    }

    public func hasStoredAPIKey(for provider: ProviderKind) -> Bool {
        secretStore.apiKey(for: provider)?.isEmpty == false
    }

    public func clearConversation() {
        transcript = Self.initialTranscript
        lastExecution = nil
        persistSnapshot()
    }

    public func resetWorkspace() {
        let sourceCount = sources.count
        let bookmarkCount = settings.bookmarks.count
        sources.removeAll()
        selectedSource = nil
        settings.bookmarks.removeAll()
        settings.queryTemplates.removeAll()
        transcript = Self.initialTranscript
        lastExecution = nil
        searchQuery = ""
        searchResults = []

        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Workspace Reset",
                body: "Cleared \(sourceCount) source\(sourceCount == 1 ? "" : "s"), \(bookmarkCount) bookmark\(bookmarkCount == 1 ? "" : "s"), and the conversation."
            )
        )
        persistSnapshot()
    }

    public func refreshProviderStatuses() {
        providerStatuses = ProviderDiagnostics.detect(
            environment: environment,
            secretStore: secretStore
        )
    }

    public func requestComposerFocus() {
        composerFocusRequestID += 1
    }

    public func transcriptItems(for role: TranscriptRole) -> [TranscriptItem] {
        transcript.filter { $0.role == role }
    }

    public var userMessageCount: Int {
        transcript.filter { $0.role == .user }.count
    }

    public var systemMessageCount: Int {
        transcript.filter { $0.role == .system }.count
    }

    public var sortedSourcesByName: [DataSource] {
        sources.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public var sortedSourcesByDate: [DataSource] {
        sources.sorted { $0.addedAt > $1.addedAt }
    }

    public var commandCount: Int {
        transcript.filter {
            if case .commandResult = $0.kind { return true }
            return false
        }.count
    }

    /// Group sources by their kind
    public var sourcesByKind: [DataSourceKind: [DataSource]] {
        Dictionary(grouping: sources, by: \.kind)
    }

    /// Filter transcript items by kind
    public func transcriptItems(matching kind: TranscriptKind) -> [TranscriptItem] {
        transcript.filter { $0.kind == kind }
    }

    /// All command previews in the transcript
    public var commandPreviews: [TranscriptItem] {
        transcript.filter {
            if case .commandPreview = $0.kind { return true }
            return false
        }
    }

    /// Most recently used sources (up to N)
    public func recentSources(limit: Int = 5) -> [DataSource] {
        Array(sortedSourcesByDate.prefix(limit))
    }

    /// Duration of the current session (from first transcript item to now)
    public var sessionDuration: TimeInterval {
        guard let firstTimestamp = transcript.first?.timestamp else { return 0 }
        return Date().timeIntervalSince(firstTimestamp)
    }

    /// Check if any source is a DuckDB database
    public var hasDatabaseSource: Bool {
        sources.contains(where: { $0.kind == .duckdb })
    }

    /// Check if any source is a file-based source (parquet, CSV, JSON)
    public var hasFileSource: Bool {
        sources.contains(where: { $0.kind != .duckdb })
    }

    /// Total number of distinct source kinds
    public var sourceKindCount: Int {
        Set(sources.map(\.kind)).count
    }

    /// Last successful execution output (if any)
    public var lastSuccessfulOutput: String? {
        guard let lastExecution, lastExecution.exitCode == 0 else { return nil }
        return lastExecution.stdout.isEmpty ? nil : lastExecution.stdout
    }

    /// Brief summary of the transcript
    public var transcriptSummary: String {
        let userCount = userMessageCount
        let commandCount = self.commandCount
        let successCount = transcript.filter {
            if case let .commandResult(exitCode, _, _) = $0.kind { return exitCode == 0 }
            return false
        }.count
        let failureCount = transcript.filter {
            if case let .commandResult(exitCode, _, _) = $0.kind { return exitCode != 0 }
            return false
        }.count
        return "\(transcript.count) items, \(userCount) user messages, \(commandCount) commands (\(successCount) ✓, \(failureCount) ✗)"
    }

    /// Paginate the transcript into pages of a given size
    public func transcriptPage(page: Int, pageSize: Int = 20) -> [TranscriptItem] {
        guard pageSize > 0, page >= 0 else { return [] }
        let start = page * pageSize
        guard start < transcript.count else { return [] }
        let end = min(start + pageSize, transcript.count)
        return Array(transcript[start..<end])
    }

    /// Search for sources by name
    public func findSources(matching query: String) -> [DataSource] {
        let lowered = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return sources }
        return sources.filter { $0.displayName.lowercased().contains(lowered) }
    }

    /// Export the session as a JSON string for backup
    public func exportSessionAsJSON() -> String? {
        let snapshot = AppSessionSnapshot(
            settings: settings,
            sources: sources,
            selectedSourceID: selectedSource?.id,
            transcript: transcript
        )
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    /// Get unique SQL commands that have been executed (deduped)
    public var uniqueCommandHistory: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in transcript {
            if case let .commandPreview(sql, _) = item.kind, seen.insert(sql).inserted {
                result.append(sql)
            }
        }
        return result
    }

    /// Total number of transcript pages
    public func transcriptPageCount(pageSize: Int = 20) -> Int {
        guard pageSize > 0 else { return 0 }
        return max(1, (transcript.count + pageSize - 1) / pageSize)
    }

    /// All command results in the transcript
    public var commandResults: [TranscriptItem] {
        transcript.filter {
            if case .commandResult = $0.kind { return true }
            return false
        }
    }

    public func searchTranscript(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = trimmed
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        searchResults = transcript.filter { item in
            item.body.localizedCaseInsensitiveContains(trimmed) ||
            item.title.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public func rerunCommand(at index: Int?) async {
        // Find commands in reverse order from the transcript
        let commandItems = transcript.compactMap { item -> (sql: String, source: DataSource)? in
            switch item.kind {
            case let .commandPreview(sql, _):
                // Find the source this was run against
                if let selectedSource {
                    return (sql, selectedSource)
                }
                return nil
            default:
                return nil
            }
        }

        guard !commandItems.isEmpty else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "No Commands",
                    body: "No previous commands found to re-run. Execute a query first."
                )
            )
            return
        }

        let reversedCommands = commandItems.reversed().map { $0 }
        let targetIndex = (index ?? 1) - 1

        guard targetIndex >= 0, targetIndex < reversedCommands.count else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Invalid Index",
                    body: "Command #\(targetIndex + 1) not found. There are \(reversedCommands.count) previous command(s)."
                )
            )
            return
        }

        let target = reversedCommands[targetIndex]
        let plan = DuckDBCommandPlan(
            source: target.source,
            sql: target.sql,
            explanation: "Re-running previous command."
        )

        appendTranscript(
            TranscriptItem(
                role: .assistant,
                title: "Re-run",
                body: "Re-executing: `\(target.sql)`",
                kind: .commandPreview(sql: target.sql, sourceName: target.source.displayName)
            )
        )

        guard let executor else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "DuckDB Unavailable",
                    body: "The app could not locate the `duckdb` binary."
                )
            )
            return
        }

        isRunning = true
        isDiagnosticsDrawerPresented = true
        defer { isRunning = false }

        do {
            let result = try await executor.execute(plan: plan)
            lastExecution = result
            appendTranscript(
                TranscriptItem(
                    role: .assistant,
                    title: result.exitCode == 0 ? "Re-run Result" : "Re-run Error",
                    body: result.exitCode == 0 ? "DuckDB finished re-running the command." : "DuckDB returned a non-zero exit code.",
                    kind: .commandResult(
                        exitCode: result.exitCode,
                        stdout: result.stdout,
                        stderr: result.stderr
                    )
                )
            )
        } catch {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Execution Failed",
                    body: error.localizedDescription
                )
            )
        }
    }

    public func undoLastUserMessage() {
        // Find and remove the last user message plus the /undo message itself
        // We already removed the thinking item, and the /undo user message was appended
        // Remove the /undo user message first
        if let undoIndex = transcript.lastIndex(where: { $0.role == .user && $0.body == "/undo" }) {
            transcript.remove(at: undoIndex)
        }

        // Now find and remove the previous user message and its response(s)
        guard let lastUserIndex = transcript.lastIndex(where: { $0.role == .user }) else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Nothing to Undo",
                    body: "No user messages found to remove."
                )
            )
            return
        }

        // Remove from the last user message to the end
        let removedCount = transcript.count - lastUserIndex
        transcript.removeSubrange(lastUserIndex...)
        persistSnapshot()

        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Undone",
                body: "Removed \(removedCount) message\(removedCount == 1 ? "" : "s") from the transcript."
            )
        )
    }

    public func bookmarkLastCommand() {
        // Find the most recent command preview
        guard let lastCommand = transcript.last(where: {
            if case .commandPreview = $0.kind { return true }
            return false
        }),
        case let .commandPreview(sql, sourceName) = lastCommand.kind else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Nothing to Bookmark",
                    body: "No commands found to bookmark. Run a query first."
                )
            )
            return
        }

        // Check for duplicates
        if settings.bookmarks.contains(where: { $0.sql == sql }) {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Already Bookmarked",
                    body: "This command is already in your bookmarks."
                )
            )
            return
        }

        let bookmark = BookmarkedCommand(sql: sql, sourceName: sourceName)
        settings.bookmarks.append(bookmark)
        persistSnapshot()

        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Bookmarked",
                body: "Saved `\(sql)` to bookmarks."
            )
        )
    }

    public func exportTranscriptToClipboard() {
        let markdown = formatTranscriptAsMarkdown()
        guard !markdown.isEmpty else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Nothing to Export",
                    body: "The transcript is empty."
                )
            )
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Exported",
                body: "Transcript (\(transcript.count) items, \(markdown.count) characters) copied to clipboard as Markdown."
            )
        )
    }

    public func formatTranscriptAsMarkdown() -> String {
        transcript.map { item in
            var line = "### \(item.title)\n\n\(item.body)"
            switch item.kind {
            case let .commandPreview(sql, sourceName):
                line += "\n\n```sql\n\(sql)\n```\n\nSource: \(sourceName)"
            case let .rawCommandPreview(command):
                line += "\n\n```\nduckdb \(command)\n```"
            case let .commandResult(exitCode, stdout, stderr):
                if !stdout.isEmpty {
                    line += "\n\n```\n\(stdout)\n```"
                }
                if !stderr.isEmpty {
                    line += "\n\nStderr:\n```\n\(stderr)\n```"
                }
                line += "\n\nExit code: \(exitCode)"
            default:
                break
            }
            return line
        }.joined(separator: "\n\n---\n\n")
    }

    public func copyLastResultToClipboard() {
        guard let lastExecution else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Nothing to Copy",
                    body: "No query results available. Run a command first."
                )
            )
            return
        }

        let text = lastExecution.stdout.isEmpty ? lastExecution.stderr : lastExecution.stdout
        guard !text.isEmpty else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Nothing to Copy",
                    body: "The last command produced no output."
                )
            )
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appendTranscript(
            TranscriptItem(
                role: .system,
                title: "Copied",
                body: "Last query result (\(text.count) characters) copied to clipboard."
            )
        )
    }

    public func runRawDuckDBCommand() async {
        let argumentsLine = manualDuckDBArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !argumentsLine.isEmpty else {
            return
        }

        await executeRawDuckDB(argumentsLine: argumentsLine, source: .diagnosticsDrawer)
        manualDuckDBArguments = ""
    }

    private func sendProviderPrompt(_ prompt: String, thinkingID: UUID? = nil) async {
        isRunning = true
        defer { isRunning = false }

        do {
            let response = try await chatResponder.respond(
                prompt: prompt,
                source: selectedSource,
                transcript: transcript,
                settings: settings,
                providerStatuses: providerStatuses
            )
            let item = TranscriptItem(
                role: .assistant,
                title: response.provider.displayName,
                body: response.text
            )
            if let thinkingID {
                replaceThinkingItem(thinkingID, with: item)
            } else {
                appendTranscript(item)
            }
        } catch {
            if let thinkingID {
                removeThinkingItem(thinkingID)
            }
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Provider Error",
                    body: error.localizedDescription
                )
            )
        }
    }

    private func executeNaturalLanguageQuery(prompt: String, source: DataSource, thinkingID: UUID) async {
        isRunning = true
        defer { isRunning = false }

        // Step 1: Ask the provider to generate SQL
        do {
            let sqlResponse = try await chatResponder.generateSQL(
                prompt: prompt,
                source: source,
                transcript: transcript,
                settings: settings,
                providerStatuses: providerStatuses
            )

            guard !sqlResponse.sql.isEmpty else {
                // Provider couldn't generate SQL — show the explanation as a normal response
                replaceThinkingItem(thinkingID, with:
                    TranscriptItem(
                        role: .assistant,
                        title: sqlResponse.provider.displayName,
                        body: sqlResponse.explanation
                    )
                )
                return
            }

            // Step 2: Show the generated SQL
            let plan = DuckDBCommandPlan(
                source: source,
                sql: sqlResponse.sql,
                explanation: sqlResponse.explanation.isEmpty ? "Generated SQL for: \(prompt)" : sqlResponse.explanation
            )

            replaceThinkingItem(thinkingID, with:
                TranscriptItem(
                    role: .assistant,
                    title: "\(sqlResponse.provider.displayName) → SQL",
                    body: plan.explanation,
                    kind: .commandPreview(sql: plan.sql, sourceName: source.displayName)
                )
            )

            // Step 3: Execute the SQL
            guard let executor else {
                appendTranscript(
                    TranscriptItem(
                        role: .system,
                        title: "DuckDB Unavailable",
                        body: "The app could not locate the `duckdb` binary. Install DuckDB or set DUCKDB_BINARY."
                    )
                )
                return
            }

            isDiagnosticsDrawerPresented = true
            let result = try await executor.execute(plan: plan)
            lastExecution = result
            appendTranscript(
                TranscriptItem(
                    role: .assistant,
                    title: result.exitCode == 0 ? "Query Result" : "Query Error",
                    body: result.exitCode == 0 ? "DuckDB finished running the generated query." : "DuckDB returned a non-zero exit code.",
                    kind: .commandResult(
                        exitCode: result.exitCode,
                        stdout: result.stdout,
                        stderr: result.stderr
                    )
                )
            )
        } catch {
            removeThinkingItem(thinkingID)
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Query Generation Failed",
                    body: error.localizedDescription
                )
            )
        }
    }

    private func replaceThinkingItem(_ thinkingID: UUID, with item: TranscriptItem) {
        if let index = transcript.firstIndex(where: { $0.id == thinkingID }) {
            transcript[index] = item
        } else {
            transcript.append(item)
        }
        persistSnapshot()
    }

    private func removeThinkingItem(_ thinkingID: UUID) {
        transcript.removeAll(where: { $0.id == thinkingID })
        persistSnapshot()
    }

    private func appendTranscript(_ item: TranscriptItem) {
        transcript.append(item)
        persistSnapshot()
    }

    private func executeRawDuckDB(argumentsLine: String, source: DuckDBRunSource) async {
        appendTranscript(
            TranscriptItem(
                role: .assistant,
                title: "DuckDB CLI",
                body: "Running raw DuckDB CLI arguments exactly as entered.",
                kind: .rawCommandPreview(command: argumentsLine)
            )
        )

        guard let executor else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "DuckDB Unavailable",
                    body: "The app could not locate the `duckdb` binary. Install DuckDB or set DUCKDB_BINARY."
                )
            )
            return
        }

        isRunning = true
        isDiagnosticsDrawerPresented = true
        defer { isRunning = false }

        do {
            let result = try await executor.executeRaw(argumentsLine: argumentsLine)
            lastExecution = result
            appendTranscript(
                TranscriptItem(
                    role: .assistant,
                    title: result.exitCode == 0 ? "DuckDB CLI Result" : "DuckDB CLI Error",
                    body: source.successMessage,
                    kind: .commandResult(
                        exitCode: result.exitCode,
                        stdout: result.stdout,
                        stderr: result.stderr
                    )
                )
            )
        } catch {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Execution Failed",
                    body: error.localizedDescription
                )
            )
        }
    }

    private func persistSnapshot() {
        try? sessionStore.saveSnapshot(
            AppSessionSnapshot(
                settings: settings,
                sources: sources,
                selectedSourceID: selectedSource?.id,
                transcript: transcript
            )
        )
    }
}

private enum DuckDBRunSource {
    case chatComposer
    case diagnosticsDrawer

    var successMessage: String {
        switch self {
        case .chatComposer:
            "DuckDB finished running the raw CLI command from the chat composer."
        case .diagnosticsDrawer:
            "DuckDB finished running the raw CLI command from the diagnostics drawer."
        }
    }
}
