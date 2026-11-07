import Foundation
import HashFleetCore

/// The durable form of a detected alert. Background refresh runs with a new FleetStore, so
/// keeping this journal in the app's shared defaults lets the next foreground launch show the
/// same event in-app after its system notification was delivered.
enum FleetNotificationEvent: Codable, Equatable, Sendable {
    case bestShare(MinerBestShareEvent)
    case blockFound(MinerBlockFoundEvent)
    case temperature(MinerTemperatureAlertEvent)
    case power(MinerPowerAlertEvent)
    case stateChange(MinerStateChangeEvent)
    case metricAlert(MinerMetricAlertEvent)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum EventType: String, Codable {
        case bestShare
        case blockFound
        case temperature
        case power
        case stateChange
        case metricAlert
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EventType.self, forKey: .type) {
        case .bestShare: self = .bestShare(try container.decode(MinerBestShareEvent.self, forKey: .value))
        case .blockFound: self = .blockFound(try container.decode(MinerBlockFoundEvent.self, forKey: .value))
        case .temperature: self = .temperature(try container.decode(MinerTemperatureAlertEvent.self, forKey: .value))
        case .power: self = .power(try container.decode(MinerPowerAlertEvent.self, forKey: .value))
        case .stateChange: self = .stateChange(try container.decode(MinerStateChangeEvent.self, forKey: .value))
        case .metricAlert: self = .metricAlert(try container.decode(MinerMetricAlertEvent.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bestShare(let event):
            try container.encode(EventType.bestShare, forKey: .type)
            try container.encode(event, forKey: .value)
        case .blockFound(let event):
            try container.encode(EventType.blockFound, forKey: .type)
            try container.encode(event, forKey: .value)
        case .temperature(let event):
            try container.encode(EventType.temperature, forKey: .type)
            try container.encode(event, forKey: .value)
        case .power(let event):
            try container.encode(EventType.power, forKey: .type)
            try container.encode(event, forKey: .value)
        case .stateChange(let event):
            try container.encode(EventType.stateChange, forKey: .type)
            try container.encode(event, forKey: .value)
        case .metricAlert(let event):
            try container.encode(EventType.metricAlert, forKey: .type)
            try container.encode(event, forKey: .value)
        }
    }

    var id: UUID {
        switch self {
        case .bestShare(let event): event.id
        case .blockFound(let event): event.id
        case .temperature(let event): event.id
        case .power(let event): event.id
        case .stateChange(let event): event.id
        case .metricAlert(let event): event.id
        }
    }

    var deviceID: UUID {
        switch self {
        case .bestShare(let event): event.deviceID
        case .blockFound(let event): event.deviceID
        case .temperature(let event): event.deviceID
        case .power(let event): event.deviceID
        case .stateChange(let event): event.deviceID
        case .metricAlert(let event): event.deviceID
        }
    }

    var occurredAt: Date {
        switch self {
        case .bestShare(let event): event.occurredAt
        case .blockFound(let event): event.occurredAt
        case .temperature(let event): event.occurredAt
        case .power(let event): event.occurredAt
        case .stateChange(let event): event.occurredAt
        case .metricAlert(let event): event.occurredAt
        }
    }

    /// Stable enough to collapse the same observation when a foreground and background store
    /// happen to poll at the same time, while still allowing a later transition to alert again.
    var dedupeKey: String {
        let bucket = Int64(occurredAt.timeIntervalSince1970 / 300)
        switch self {
        case .bestShare(let event):
            return "best-share|\(event.deviceID.uuidString)|\(event.kind.rawValue)|\(event.rawValue)"
        case .blockFound(let event):
            return "block-found|\(event.deviceID.uuidString)|\(event.count.map { String($0) } ?? "-")|\(event.height.map { String($0) } ?? "-")"
        case .temperature(let event):
            return "temperature|\(event.deviceID.uuidString)|\(event.temperatureCelsius)|\(event.thresholdCelsius)|\(bucket)"
        case .power(let event):
            return "power|\(event.deviceID.uuidString)|\(event.kind.rawValue)|\(event.watts)|\(event.thresholdWatts)|\(bucket)"
        case .stateChange(let event):
            return "state|\(event.deviceID.uuidString)|\(event.kind.rawValue)|\(bucket)"
        case .metricAlert(let event):
            return "metric|\(event.deviceID.uuidString)|\(event.kind.rawValue)|\(bucket)"
        }
    }
}

struct FleetNotificationInboxEntry: Codable, Equatable, Identifiable, Sendable {
    let event: FleetNotificationEvent
    var systemDelivered: Bool
    var inAppDelivered: Bool

    var id: UUID { event.id }
    var dedupeKey: String { event.dedupeKey }
}
