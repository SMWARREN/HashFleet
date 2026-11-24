//
//  FleetHaptics.swift
//  HashFleet
//
//  Centralized tactile haptic feedback with tiered intensity levels:
//  - selection: picker, tab, segment changes
//  - light: item discovery, list taps, toggles
//  - medium: starting scans, confirming settings, primary buttons
//  - heavy: hardware restarts, power toggles, destructive actions
//  - success: completed fleet adds, successful scans
//  - warning: blocked actions, validation warnings
//  - error: failed connections, API rejections
//

import Foundation

#if canImport(UIKit)
import UIKit

@MainActor
public enum FleetHaptics {
    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    public static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    public static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    public static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    public static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    public static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
#else
public enum FleetHaptics {
    public static func selection() {}
    public static func light() {}
    public static func medium() {}
    public static func heavy() {}
    public static func soft() {}
    public static func rigid() {}
    public static func success() {}
    public static func warning() {}
    public static func error() {}
}
#endif
