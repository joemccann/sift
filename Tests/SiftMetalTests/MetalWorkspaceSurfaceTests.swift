import XCTest
@testable import SiftCore
@testable import SiftMetal

final class MetalWorkspaceSurfaceTests: XCTestCase {
    func testVisualizationNormalizesSnapshotIntoSignals() {
        let snapshot = MetalWorkspaceSnapshot(
            destination: .assistant,
            provider: .claude,
            sourceKind: .parquet,
            sourceCount: 2,
            transcriptCount: 7,
            providerReadiness: 2,
            executionState: .success,
            commandDurationMilliseconds: 420,
            commandOutputBytes: 2_048,
            isRunning: true
        )

        let visualization = MetalWorkspaceVisualization(snapshot: snapshot, signalCount: 32)

        XCTAssertEqual(visualization.signalBars.count, 32)
        XCTAssertTrue(visualization.signalBars.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(visualization.runIntensity, 1)
        XCTAssertGreaterThan(visualization.transcriptDensity, 0)
        XCTAssertGreaterThan(visualization.commandStateWeight, 0)
    }

    func testVisualizationRespondsToFailureState() {
        let success = MetalWorkspaceVisualization(
            snapshot: MetalWorkspaceSnapshot(
                destination: .assistant,
                provider: .openAI,
                sourceKind: .duckdb,
                sourceCount: 1,
                transcriptCount: 4,
                providerReadiness: 1,
                executionState: .success,
                commandDurationMilliseconds: 300,
                commandOutputBytes: 800,
                isRunning: false
            ),
            signalCount: 24
        )
        let failure = MetalWorkspaceVisualization(
            snapshot: MetalWorkspaceSnapshot(
                destination: .assistant,
                provider: .openAI,
                sourceKind: .duckdb,
                sourceCount: 1,
                transcriptCount: 4,
                providerReadiness: 1,
                executionState: .failure,
                commandDurationMilliseconds: 300,
                commandOutputBytes: 800,
                isRunning: false
            ),
            signalCount: 24
        )

        XCTAssertGreaterThan(failure.commandStateWeight, success.commandStateWeight)
        XCTAssertNotEqual(failure.signalBars, success.signalBars)
    }

    func testShaderSourceURLPointsAtBundledMetalSource() {
        let sourceURL = MetalShaderLibrary.shaderSourceURL()

        XCTAssertEqual(sourceURL.lastPathComponent, "SiftMetalShaders.metal")
    }

    func testVisualizationIdleStateHasZeroCommandWeight() {
        let snapshot = MetalWorkspaceSnapshot(
            destination: .assistant,
            provider: .claude,
            sourceKind: nil,
            sourceCount: 0,
            transcriptCount: 1,
            providerReadiness: 0,
            executionState: .idle,
            commandDurationMilliseconds: 0,
            commandOutputBytes: 0,
            isRunning: false
        )

        let visualization = MetalWorkspaceVisualization(snapshot: snapshot, signalCount: 16)

        XCTAssertEqual(visualization.commandStateWeight, 0)
        XCTAssertEqual(visualization.runIntensity, 0)
        XCTAssertEqual(visualization.commandDurationMilliseconds, 0)
    }

    func testVisualizationJSONSourceKindProducesValidSignals() {
        let snapshot = MetalWorkspaceSnapshot(
            destination: .assistant,
            provider: .gemini,
            sourceKind: .json,
            sourceCount: 1,
            transcriptCount: 5,
            providerReadiness: 1,
            executionState: .success,
            commandDurationMilliseconds: 100,
            commandOutputBytes: 500,
            isRunning: false
        )

        let visualization = MetalWorkspaceVisualization(snapshot: snapshot, signalCount: 24)

        XCTAssertEqual(visualization.signalBars.count, 24)
        XCTAssertTrue(visualization.signalBars.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testVisualizationCSVSourceKindProducesValidSignals() {
        let snapshot = MetalWorkspaceSnapshot(
            destination: .transcripts,
            provider: .openAI,
            sourceKind: .csv,
            sourceCount: 3,
            transcriptCount: 10,
            providerReadiness: 2,
            executionState: .success,
            commandDurationMilliseconds: 200,
            commandOutputBytes: 1024,
            isRunning: false
        )

        let visualization = MetalWorkspaceVisualization(snapshot: snapshot, signalCount: 48)

        XCTAssertEqual(visualization.signalBars.count, 48)
        XCTAssertTrue(visualization.signalBars.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testVisualizationMinSignalCountIsEnforced() {
        let snapshot = MetalWorkspaceSnapshot(
            destination: .assistant,
            provider: .claude,
            sourceKind: nil,
            sourceCount: 0,
            transcriptCount: 0,
            providerReadiness: 0,
            executionState: .idle,
            commandDurationMilliseconds: 0,
            commandOutputBytes: 0,
            isRunning: false
        )

        let visualization = MetalWorkspaceVisualization(snapshot: snapshot, signalCount: 4)

        // Minimum is 12 even if we request fewer
        XCTAssertGreaterThanOrEqual(visualization.signalBars.count, 12)
    }

    func testVisualizationDifferentDestinationsProduceDifferentSignals() {
        let snapshotA = MetalWorkspaceSnapshot(
            destination: .assistant,
            provider: .claude,
            sourceKind: .parquet,
            sourceCount: 1,
            transcriptCount: 3,
            providerReadiness: 1,
            executionState: .idle,
            commandDurationMilliseconds: 0,
            commandOutputBytes: 0,
            isRunning: false
        )
        let snapshotB = MetalWorkspaceSnapshot(
            destination: .settings,
            provider: .claude,
            sourceKind: .parquet,
            sourceCount: 1,
            transcriptCount: 3,
            providerReadiness: 1,
            executionState: .idle,
            commandDurationMilliseconds: 0,
            commandOutputBytes: 0,
            isRunning: false
        )

        let vizA = MetalWorkspaceVisualization(snapshot: snapshotA, signalCount: 24)
        let vizB = MetalWorkspaceVisualization(snapshot: snapshotB, signalCount: 24)

        XCTAssertNotEqual(vizA.signalBars, vizB.signalBars)
    }

    func testVisualizationDensityClamps() {
        let snapshot = MetalWorkspaceSnapshot(
            destination: .assistant,
            provider: .claude,
            sourceKind: .parquet,
            sourceCount: 100,
            transcriptCount: 1000,
            providerReadiness: 10,
            executionState: .success,
            commandDurationMilliseconds: 100_000,
            commandOutputBytes: 1_000_000,
            isRunning: true
        )

        let visualization = MetalWorkspaceVisualization(snapshot: snapshot, signalCount: 24)

        // All signals should still be clamped to [0,1]
        XCTAssertTrue(visualization.signalBars.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(visualization.runIntensity, 1)
        // Densities should clamp at 1
        XCTAssertLessThanOrEqual(visualization.transcriptDensity, 1)
        XCTAssertLessThanOrEqual(visualization.sourceDensity, 1)
        XCTAssertLessThanOrEqual(visualization.readinessFraction, 1)
    }
}
