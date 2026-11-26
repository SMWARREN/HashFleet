import SwiftUI
import AppKit
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Tests evaluating the retained state banner, pool diagnostics banner, and error branches
/// in FirmwareTelemetryView. Completely offline: uses in-memory MinerInfo and view modifiers.
@Suite("Firmware Telemetry Retained And Diagnostics Evaluation", .serialized)
@MainActor
struct FirmwareTelemetryDiagnosticsTests {
    private func evaluate<V: View>(_ view: V, width: CGFloat = 800, height: CGFloat = 1000) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.contentView = nil
    }

    @Test func evaluateFirmwareTelemetryRetainedAndPoolDiagnostics() {
        let rawInfo: [String: JSONValue] = [
            "hostname": .string("AxeBeta"),
            "hashRate": .number(1250),
            "expectedHashrate": .null, // Nominal reference not reported branch
            "hashrateMonitor": .object([
                "asics": .array([
                    .object(["domains": .array([.integer(400), .integer(420)])])
                ])
            ]),
            "poolBanner": .string("Stratum pool failover notice"),
            "primaryPoolError": .string("Socket connection refused"),
            "isUsingFallbackStratum": .bool(true),
            "stratumURL": .string("solo.ckpool.org"),
            "stratumPort": .integer(3333)
        ]
        let info = MinerInfo(raw: rawInfo)

        // 1. Reconnecting state (isReconnecting = true, error = nil)
        let reconnectingView = FirmwareTelemetryView(
            info: info,
            observedAt: Date(),
            minerIdentity: "miner-1",
            isCached: false,
            error: nil,
            isReconnecting: true,
            freshness: nil,
            initiallyExpanded: true
        )
        evaluate(reconnectingView)

        // 2. Cached / error retained state (isCached = true, error != nil)
        let cachedErrorView = FirmwareTelemetryView(
            info: info,
            observedAt: Date(),
            minerIdentity: "miner-2",
            isCached: true,
            error: "Connection timed out",
            isReconnecting: false,
            freshness: nil,
            initiallyExpanded: true
        )
        evaluate(cachedErrorView)

        // 3. Normal expanded state without banner/error
        let plainInfo = MinerInfo(raw: [
            "hostname": .string("AxeGamma"),
            "isUsingFallbackStratum": .null
        ])
        let plainView = FirmwareTelemetryView(
            info: plainInfo,
            observedAt: Date(),
            minerIdentity: "miner-3",
            isCached: false,
            error: nil,
            isReconnecting: false,
            freshness: nil,
            initiallyExpanded: false
        )
        evaluate(plainView)
    }
}
