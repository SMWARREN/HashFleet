//
//  FleetChangeEffectsTests.swift
//  MacAppTests
//
//  One-shot change effects (adapted from ShipSwift SWChangeEffect) fire only on genuine increases.
//

import Foundation
import Testing
@testable import HashFleetMac

@Suite("Change effects")
struct FleetChangeEffectsTests {
    @Test func firstReadingOnlyRecordsABaseline() {
        var detector = FleetIncreaseDetector<Int>()
        #expect(detector.observe(120) == nil)
        #expect(detector.last == 120)
    }

    @Test func increaseFiresWithThePreviousValue() {
        var detector = FleetIncreaseDetector<Int>(last: 120)
        #expect(detector.observe(123) == 120)
        #expect(detector.last == 123)
    }

    @Test func sameValueDoesNotFire() {
        var detector = FleetIncreaseDetector<Int>(last: 120)
        #expect(detector.observe(120) == nil)
    }

    @Test func dropAfterRebootReBaselinesWithoutFiring() {
        var detector = FleetIncreaseDetector<Int>(last: 5_000)
        #expect(detector.observe(3) == nil)
        #expect(detector.last == 3)
        #expect(detector.observe(4) == 3)
    }

    @Test func missingReadingIsIgnoredAndKeepsBaseline() {
        var detector = FleetIncreaseDetector<Int>(last: 120)
        #expect(detector.observe(nil) == nil)
        #expect(detector.last == 120)
        #expect(detector.observe(121) == 120)
    }

    @Test func bestShareDecimalIncrease() {
        var detector = FleetIncreaseDetector<Decimal>(last: Decimal(string: "1500000000")!)
        #expect(detector.observe(Decimal(string: "1400000000")!) == nil)
        #expect(detector.observe(Decimal(string: "2100000000")!) == Decimal(string: "1400000000")!)
    }

    @Test func riseText() {
        #expect(FleetShareRiseText.text(previous: 10, current: 11) == "+1")
        #expect(FleetShareRiseText.text(previous: 10, current: 22) == "+12")
        #expect(FleetShareRiseText.text(previous: 0, current: 5_000) == "+999+")
        #expect(FleetShareRiseText.text(previous: 10, current: 10) == nil)
        #expect(FleetShareRiseText.text(previous: 10, current: 4) == nil)
    }
}
