//
//  MinerSidebarAttentionTests.swift
//  MacAppTests
//
//  Sidebar miner rows call out only problems with a status pill (adapted from ShipSwift SWStatusBadge).
//

import Foundation
import Testing
@testable import HashFleetMac

@Suite("Sidebar miner status pills")
struct MinerSidebarAttentionTests {
    @Test func healthyMinersGetNoPill() {
        #expect(MinerSidebarAttention.resolve(state: .live, temperature: 52) == nil)
        #expect(MinerSidebarAttention.resolve(state: .online, temperature: 69.9) == nil)
        #expect(MinerSidebarAttention.resolve(state: .live, temperature: nil) == nil)
    }

    @Test func unreachableAndStaleMinersShowOffline() {
        #expect(MinerSidebarAttention.resolve(state: .unreachable, temperature: nil) == .offline)
        // Stale keeps old readings, but an old 80 °C must not read as a live hot warning.
        #expect(MinerSidebarAttention.resolve(state: .stale, temperature: 80) == .offline)
    }

    @Test func hotAtOrAboveThreshold() {
        #expect(MinerSidebarAttention.resolve(state: .live, temperature: 70) == .hot(celsius: 70))
        #expect(MinerSidebarAttention.resolve(state: .online, temperature: 74.6) == .hot(celsius: 74.6))
    }

    @Test func transientStatesStayQuiet() {
        for state: FleetMinerPresentationState in [.sample, .loading, .connecting, .reconnecting] {
            #expect(MinerSidebarAttention.resolve(state: state, temperature: 90) == nil)
        }
    }

    @Test func nonFiniteTemperatureIsIgnored() {
        #expect(MinerSidebarAttention.resolve(state: .live, temperature: .infinity) == nil)
        #expect(MinerSidebarAttention.resolve(state: .live, temperature: .nan) == nil)
    }

    @Test func pillText() {
        #expect(MinerSidebarAttention.offline.text == "Offline")
        #expect(MinerSidebarAttention.hot(celsius: 72).text.hasPrefix("Hot 72"))
        #expect(MinerSidebarAttention.hot(celsius: 72).text.hasSuffix("°C"))
    }

    @Test func overviewCardsShowOnlyHot() {
        #expect(MinerSidebarAttention.hotOnly(state: .live, temperature: 71) == .hot(celsius: 71))
        #expect(MinerSidebarAttention.hotOnly(state: .unreachable, temperature: nil) == nil)
        #expect(MinerSidebarAttention.hotOnly(state: .stale, temperature: 85) == nil)
        #expect(MinerSidebarAttention.hotOnly(state: .live, temperature: 60) == nil)
    }
}
