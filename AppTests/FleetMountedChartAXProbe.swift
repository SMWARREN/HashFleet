#if canImport(UIKit)
import UIKit
import Accessibility

/// Scratch-only candidate observer. Reads the installed accessibility hierarchy.
/// A bounded traversal miss is an inconclusive observation, never proof of absence.
@MainActor
struct MountedChartAXProbe {
    struct SeriesObservation {
        let name: String?
        let pointCount: Int
        let latestPoints: [(timestamp: Double, value: Double?)]
    }

    struct Observation {
        var targetFound = false
        var conformsToAXChart = false
        var descriptorAvailable = false
        var descriptorTitle: String?
        var yAxisTitle: String?
        var chartValue: String?
        var series: [SeriesObservation] = []
        var visited = 0
        var exhaustedVisitBudget = false
        var truncatedDepthOrChildren = false
    }

    static func inspect(root: UIView) -> Observation {
        var result = Observation()
        var pending: [(NSObject, Int)] = [(root, 0)]
        var visited: Set<ObjectIdentifier> = []
        while let (node, depth) = pending.popLast() {
            guard result.visited < 256 else {
                result.exhaustedVisitBudget = true
                break
            }
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            result.visited += 1
            let identifier = (node as? any UIAccessibilityIdentification)?.accessibilityIdentifier
            if identifier == "dashboard.historyChart" {
                result.targetFound = true
                result.chartValue = node.accessibilityValue
                if let chart = node as? any AXChart {
                    result.conformsToAXChart = true
                    if let descriptor = chart.accessibilityChartDescriptor {
                        result.descriptorAvailable = true
                        result.descriptorTitle = descriptor.title
                        result.yAxisTitle = descriptor.yAxis?.title
                        result.series = descriptor.series.map { series in
                            let maximumX = series.dataPoints.map { $0.xValue.__number }.max()
                            let latest = series.dataPoints.filter { $0.xValue.__number == maximumX }
                            return SeriesObservation(
                                name: series.name,
                                pointCount: series.dataPoints.count,
                                latestPoints: latest.map { ($0.xValue.__number, $0.yValue?.__number) }
                            )
                        }
                        return result
                    }
                }
            }
            guard depth < 24 else {
                result.truncatedDepthOrChildren = true
                continue
            }
            if let view = node as? UIView {
                if view.subviews.count > 128 { result.truncatedDepthOrChildren = true }
                for child in view.subviews.prefix(128).reversed() {
                    pending.append((child, depth + 1))
                }
            }
            let explicitChildren = node.accessibilityElements ?? []
            if !explicitChildren.isEmpty {
                if explicitChildren.count > 128 { result.truncatedDepthOrChildren = true }
                for child in explicitChildren.prefix(128).reversed() {
                    if let child = child as? NSObject { pending.append((child, depth + 1)) }
                }
            } else {
                let count = node.accessibilityElementCount()
                if count > 0 && count != NSNotFound {
                    if count > 128 { result.truncatedDepthOrChildren = true }
                    for index in (0..<min(count, 128)).reversed() {
                        if let child = node.accessibilityElement(at: index) as? NSObject {
                            pending.append((child, depth + 1))
                        }
                    }
                }
            }
        }
        return result
    }
}
#endif
