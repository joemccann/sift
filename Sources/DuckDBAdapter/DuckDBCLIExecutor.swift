import Foundation
import SiftCore

public enum DuckDBCLIError: Error, LocalizedError, Equatable {
    case binaryNotFound
    case launchFailed(String)
    case invalidArguments(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            "Could not locate the `duckdb` binary. Install DuckDB or set DUCKDB_BINARY."
        case let .launchFailed(message):
            "Failed to launch DuckDB: \(message)"
        case let .invalidArguments(message):
            message
        }
    }
}

public struct DuckDBExecutionRequest: Equatable, Sendable {
    public let binaryPath: String
    public let arguments: [String]
    public let sql: String
    public let source: DataSource?
}

public struct DuckDBExecutionResult: Equatable, Sendable {
    public let binaryPath: String
    public let arguments: [String]
    public let sql: String
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let startedAt: Date
    public let endedAt: Date
}

public final class DuckDBCLIExecutor: @unchecked Sendable {
    public let binaryPath: String
    private let environment: [String: String]

    public init(
        binaryPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws {
        if let binaryPath {
            self.binaryPath = binaryPath
        } else if let discovered = DuckDBBinaryLocator.locate(environment: environment, fileManager: fileManager) {
            self.binaryPath = discovered
        } else {
            throw DuckDBCLIError.binaryNotFound
        }

        self.environment = environment
    }

    public static func request(for plan: DuckDBCommandPlan, binaryPath: String) -> DuckDBExecutionRequest {
        let arguments: [String]

        switch plan.source.kind {
        case .duckdb:
            arguments = [
                plan.source.path,
                "-readonly",
                "-table",
                "-c",
                plan.sql,
            ]
        case .parquet, .csv, .json:
            arguments = [
                ":memory:",
                "-table",
                "-c",
                plan.sql,
            ]
        }

        return DuckDBExecutionRequest(
            binaryPath: binaryPath,
            arguments: arguments,
            sql: plan.sql,
            source: plan.source
        )
    }

    public static func request(forRawArguments arguments: [String], binaryPath: String) -> DuckDBExecutionRequest {
        DuckDBExecutionRequest(
            binaryPath: binaryPath,
            arguments: arguments,
            sql: arguments.joined(separator: " "),
            source: nil
        )
    }

    public func discoverSchema(for source: DataSource) async throws -> [DiscoveredTable] {
        guard source.kind == .duckdb else { return [] }

        let schemaSQL = """
        SELECT table_schema, table_name, column_name, data_type
        FROM information_schema.columns
        ORDER BY table_schema, table_name, ordinal_position;
        """

        let plan = DuckDBCommandPlan(source: source, sql: schemaSQL, explanation: "Schema discovery")
        let result = try await execute(plan: plan)
        guard result.exitCode == 0 else { return [] }

        return Self.parseSchemaOutput(result.stdout)
    }

    public static func parseSchemaOutput(_ output: String) -> [DiscoveredTable] {
        var tableMap: [(key: String, schema: String, name: String, columns: [DiscoveredColumn])] = []

        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 4 else { continue }
            let schema = parts[0]
            let table = parts[1]
            let column = parts[2]
            let dataType = parts[3]

            // Skip header row
            guard schema != "table_schema" else { continue }

            let key = "\(schema).\(table)"
            if let idx = tableMap.firstIndex(where: { $0.key == key }) {
                tableMap[idx].columns.append(DiscoveredColumn(name: column, type: dataType))
            } else {
                tableMap.append((key: key, schema: schema, name: table, columns: [DiscoveredColumn(name: column, type: dataType)]))
            }
        }

        return tableMap.map { DiscoveredTable(schema: $0.schema, name: $0.name, columns: $0.columns) }
    }

    public func execute(plan: DuckDBCommandPlan) async throws -> DuckDBExecutionResult {
        let request = Self.request(for: plan, binaryPath: binaryPath)
        return try await execute(request: request)
    }

    public func executeRaw(argumentsLine: String) async throws -> DuckDBExecutionResult {
        let arguments: [String]
        do {
            arguments = try DuckDBRawArgumentParser.parse(argumentsLine)
        } catch let error as DuckDBRawArgumentParser.Error {
            throw DuckDBCLIError.invalidArguments(error.localizedDescription)
        } catch {
            throw error
        }

        return try await execute(request: Self.request(forRawArguments: arguments, binaryPath: binaryPath))
    }

    private func execute(request: DuckDBExecutionRequest) async throws -> DuckDBExecutionResult {
        let environment = self.environment

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: request.binaryPath)
            process.arguments = request.arguments
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let startedAt = Date()
            do {
                try process.run()
            } catch {
                throw DuckDBCLIError.launchFailed(error.localizedDescription)
            }

            process.waitUntilExit()
            let endedAt = Date()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            return DuckDBExecutionResult(
                binaryPath: request.binaryPath,
                arguments: request.arguments,
                sql: request.sql,
                stdout: String(decoding: stdoutData, as: UTF8.self),
                stderr: String(decoding: stderrData, as: UTF8.self),
                exitCode: process.terminationStatus,
                startedAt: startedAt,
                endedAt: endedAt
            )
        }.value
    }
}
