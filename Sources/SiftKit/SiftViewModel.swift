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
    @Published public private(set) var providerStatuses: [ProviderStatus]
    @Published public private(set) var settings: AppSettings
    @Published public var manualDuckDBArguments = ""
    @Published public var composerFocusRequestID = 0
    @Published public var isDiagnosticsDrawerPresented = false
    @Published public var isSetupFlowPresented = false
    @Published public private(set) var isRunning = false

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

    public func importSource(url: URL) {
        guard let source = DataSource.from(url: url) else {
            appendTranscript(
                TranscriptItem(
                    role: .system,
                    title: "Unsupported Source",
                    body: "Only `.duckdb`, `.db`, `.parquet`, `.csv`, and `.tsv` files are supported."
                )
            )
            return
        }

        if !sources.contains(source) {
            sources.insert(source, at: 0)
        }
        selectedSource = source
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

    public func refreshProviderStatuses() {
        providerStatuses = ProviderDiagnostics.detect(
            environment: environment,
            secretStore: secretStore
        )
    }

    public func requestComposerFocus() {
        composerFocusRequestID += 1
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
