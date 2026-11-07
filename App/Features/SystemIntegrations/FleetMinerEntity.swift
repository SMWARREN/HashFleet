import AppIntents
import Foundation
import HashFleetCore

@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
public struct FleetMinerEntity: AppEntity, Identifiable, Sendable {
    public static let defaultQuery = FleetMinerEntityQuery()

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Miner")
    }

    public let id: String
    public let name: String
    public let address: String

    public init(id: String, name: String, address: String) {
        self.id = id
        self.name = name
        self.address = address
    }

    public init(device: MinerDevice) {
        self.id = device.id.uuidString
        self.name = device.name
        self.address = device.address
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(address)"
        )
    }
}

@available(iOS 17.0, macOS 14.0, watchOS 10.0, tvOS 17.0, *)
public struct FleetMinerEntityQuery: EntityStringQuery, Sendable {
    private let loader: (@Sendable () -> [MinerDevice])?

    public init() {
        self.loader = nil
    }

    public init(loader: @escaping @Sendable () -> [MinerDevice]) {
        self.loader = loader
    }

    public func entities(for identifiers: [String]) async throws -> [FleetMinerEntity] {
        let all = loadValidEntities()
        let idSet = Set(identifiers)
        return all.filter { idSet.contains($0.id) }
    }

    public func entities(matching string: String) async throws -> [FleetMinerEntity] {
        let all = loadValidEntities()
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return all }
        return all.filter {
            $0.name.lowercased().contains(query) || $0.address.lowercased().contains(query)
        }
    }

    public func suggestedEntities() async throws -> [FleetMinerEntity] {
        loadValidEntities()
    }

    private func loadValidEntities() -> [FleetMinerEntity] {
        if loader == nil && FleetHardwareControlGate.shared.isBlocked { return [] }
        let devices = loader?() ?? FleetMinerControlExecutor.sharedSavedDevicesLoader()
        return devices.compactMap { device in
            guard (try? device.validatedURL()) != nil else {
                return nil
            }
            return FleetMinerEntity(device: device)
        }
    }
}
