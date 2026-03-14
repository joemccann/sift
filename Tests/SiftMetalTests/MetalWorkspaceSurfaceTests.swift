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

    func testVisualizationDifferentProvidersProduceDifferentSignals() {
        let snapshotClaude = MetalWorkspaceSnapshot(
            destination: .assistant, provider: .claude, sourceKind: .parquet,
            sourceCount: 1, transcriptCount: 3, providerReadiness: 1,
            executionState: .idle, commandDurationMilliseconds: 0,
            commandOutputBytes: 0, isRunning: false
        )
        let snapshotGemini = MetalWorkspaceSnapshot(
            destination: .assistant, provider: .gemini, sourceKind: .parquet,
            sourceCount: 1, transcriptCount: 3, providerReadiness: 1,
            executionState: .idle, commandDurationMilliseconds: 0,
            commandOutputBytes: 0, isRunning: false
        )

        let vizClaude = MetalWorkspaceVisualization(snapshot: snapshotClaude, signalCount: 24)
        let vizGemini = MetalWorkspaceVisualization(snapshot: snapshotGemini, signalCount: 24)
        XCTAssertNotEqual(vizClaude.signalBars, vizGemini.signalBars)
    }
}

// MARK: - MetalDeviceCapabilities

final class MetalDeviceCapabilitiesTests: XCTestCase {
    func testSummaryBadgesIncludesName() {
        let caps = MetalDeviceCapabilities(
            name: "Apple M1",
            isLowPower: false,
            hasUnifiedMemory: true,
            supportsDynamicLibraries: true,
            recommendedMaxWorkingSetSizeMB: 8192
        )

        let badges = caps.summaryBadges
        XCTAssertTrue(badges.contains("Apple M1"))
        XCTAssertTrue(badges.contains("Unified memory"))
        XCTAssertTrue(badges.contains("High throughput"))
        XCTAssertTrue(badges.contains("Dynamic libraries"))
        XCTAssertTrue(badges.contains("8192 MB working set"))
    }

    func testLowPowerBadge() {
        let caps = MetalDeviceCapabilities(
            name: "Intel UHD",
            isLowPower: true,
            hasUnifiedMemory: false,
            supportsDynamicLibraries: false,
            recommendedMaxWorkingSetSizeMB: nil
        )

        let badges = caps.summaryBadges
        XCTAssertTrue(badges.contains("Low power"))
        XCTAssertTrue(badges.contains("Discrete memory"))
        XCTAssertFalse(badges.contains("Dynamic libraries"))
        XCTAssertFalse(badges.contains { $0.contains("MB working set") })
    }

    func testEquality() {
        let a = MetalDeviceCapabilities(
            name: "GPU", isLowPower: false, hasUnifiedMemory: true,
            supportsDynamicLibraries: true, recommendedMaxWorkingSetSizeMB: 4096
        )
        let b = MetalDeviceCapabilities(
            name: "GPU", isLowPower: false, hasUnifiedMemory: true,
            supportsDynamicLibraries: true, recommendedMaxWorkingSetSizeMB: 4096
        )
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = MetalDeviceCapabilities(
            name: "GPU A", isLowPower: false, hasUnifiedMemory: true,
            supportsDynamicLibraries: true, recommendedMaxWorkingSetSizeMB: 4096
        )
        let b = MetalDeviceCapabilities(
            name: "GPU B", isLowPower: true, hasUnifiedMemory: false,
            supportsDynamicLibraries: false, recommendedMaxWorkingSetSizeMB: nil
        )
        XCTAssertNotEqual(a, b)
    }

    func testCurrentReturnsNilWhenNoDevice() {
        let caps = MetalDeviceInspector.current(makeDefaultDevice: { nil })
        XCTAssertNil(caps)
    }
}

// MARK: - Visualization edge cases

final class VisualizationEdgeCaseTests: XCTestCase {
    func testVisualizationWithTranscriptsDestination() {
        let snapshot = MetalWorkspaceSnapshot(
            destination: .transcripts,
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

        let viz = MetalWorkspaceVisualization(snapshot: snapshot, signalCount: 16)
        XCTAssertEqual(viz.signalBars.count, 16)
        XCTAssertTrue(viz.signalBars.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testVisualizationWithSetupDestination() {
        let snapshot = MetalWorkspaceSnapshot(
            destination: .setup,
            provider: .gemini,
            sourceKind: nil,
            sourceCount: 0,
            transcriptCount: 1,
            providerReadiness: 0,
            executionState: .idle,
            commandDurationMilliseconds: 0,
            commandOutputBytes: 0,
            isRunning: false
        )

        let viz = MetalWorkspaceVisualization(snapshot: snapshot, signalCount: 24)
        XCTAssertEqual(viz.signalBars.count, 24)
        XCTAssertEqual(viz.runIntensity, 0)
    }

    func testVisualizationWithLargeOutput() {
        let snapshot = MetalWorkspaceSnapshot(
            destination: .assistant,
            provider: .openAI,
            sourceKind: .duckdb,
            sourceCount: 5,
            transcriptCount: 50,
            providerReadiness: 3,
            executionState: .success,
            commandDurationMilliseconds: 5000,
            commandOutputBytes: 100_000,
            isRunning: false
        )

        let viz = MetalWorkspaceVisualization(snapshot: snapshot, signalCount: 48)
        XCTAssertEqual(viz.signalBars.count, 48)
        XCTAssertTrue(viz.signalBars.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertLessThanOrEqual(viz.commandOutputScale, 1.0)
    }

    func testVisualizationSourceDensityScaling() {
        let noSources = MetalWorkspaceVisualization(
            snapshot: MetalWorkspaceSnapshot(
                destination: .assistant, provider: .claude, sourceKind: nil,
                sourceCount: 0, transcriptCount: 0, providerReadiness: 0,
                executionState: .idle, commandDurationMilliseconds: 0,
                commandOutputBytes: 0, isRunning: false
            ), signalCount: 12
        )

        let manySources = MetalWorkspaceVisualization(
            snapshot: MetalWorkspaceSnapshot(
                destination: .assistant, provider: .claude, sourceKind: .parquet,
                sourceCount: 10, transcriptCount: 0, providerReadiness: 0,
                executionState: .idle, commandDurationMilliseconds: 0,
                commandOutputBytes: 0, isRunning: false
            ), signalCount: 12
        )

        XCTAssertLessThan(noSources.sourceDensity, manySources.sourceDensity)
    }
}
