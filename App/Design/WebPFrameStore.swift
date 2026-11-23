import CryptoKit
import Foundation
import ImageIO

/// Immutable metadata crosses executors. ImageIO sources stay inside the store's actor.
struct WebPAnimation: Sendable {
    let id: String
    let data: Data
    let durations: [TimeInterval]
    let width: Int
    let height: Int

    var duration: TimeInterval { durations.reduce(0, +) }

    func frameIndex(at elapsed: TimeInterval) -> Int {
        guard duration > 0, elapsed.isFinite, elapsed >= 0 else { return 0 }
        var remaining = elapsed.truncatingRemainder(dividingBy: duration)
        for (index, delay) in durations.enumerated() {
            if remaining < delay { return index }
            remaining -= delay
        }
        return max(0, durations.count - 1)
    }
}

struct WebPPixelSize: Hashable, Sendable {
    enum Geometry: Hashable, Sendable { case aspectFit, logicalSize }
    let width: Int
    let height: Int
    private let geometry: Geometry

    init?(displaySize: CGSize, scale: CGFloat, geometry: Geometry = .aspectFit) {
        guard displaySize.width.isFinite, displaySize.height.isFinite, scale.isFinite,
              displaySize.width > 0, displaySize.height > 0, scale > 0 else { return nil }
        let width = ceil(displaySize.width * scale)
        let height = ceil(displaySize.height * scale)
        guard width.isFinite, height.isFinite, width <= 4096, height <= 4096 else { return nil }
        self.width = Int(width)
        self.height = Int(height)
        self.geometry = geometry
    }

    func fitting(_ animation: WebPAnimation) -> WebPPixelSize {
        // AppKit has always assigned displaySize as the NSImage's logical size, even
        // for non-square consumers. Rasterize that same geometry, without undersampling
        // its wider dimension or silently changing the approved appearance.
        if geometry == .logicalSize {
            let factor = min(1, Double(animation.width) / Double(width), Double(animation.height) / Double(height))
            return WebPPixelSize(width: max(1, Int(ceil(Double(width) * factor))),
                                 height: max(1, Int(ceil(Double(height) * factor))))
        }
        let factor = min(1, Double(width) / Double(animation.width), Double(height) / Double(animation.height))
        return WebPPixelSize(width: max(1, Int(ceil(Double(animation.width) * factor))),
                             height: max(1, Int(ceil(Double(animation.height) * factor))))
    }

    private init(width: Int, height: Int) {
        self.width = width
        self.height = height
        geometry = .aspectFit
    }

    var bytesPerRow: Int { (width * 4 + 63) & ~63 }
    var byteCost: Int { bytesPerRow * height }
}

/// A displayed or in-flight frame remains charged to the cache until its last lease dies.
/// The image is an immutable, already rasterized bitmap, never a shared ImageIO source.
final class WebPFrameLease: Sendable {
    let image: CGImage
    let index: Int
    let byteCost: Int
    private let relinquish: @Sendable () -> Void

    init(image: CGImage, index: Int, byteCost: Int, relinquish: @escaping @Sendable () -> Void) {
        self.image = image
        self.index = index
        self.byteCost = byteCost
        self.relinquish = relinquish
    }

    deinit { relinquish() }
}

/// One serial, non-main executor owns all decoding. A frame is explicitly drawn into a
/// display-sized bitmap here, so lazy ImageIO decompression cannot migrate to a UI tick.
/// Small loops fit and are reused on subsequent passes. Larger loops use the same bounded
/// LRU, rather than predecoding an unbounded array or changing the artwork's resolution.
actor WebPFrameStore {
    static let shared = WebPFrameStore()

    enum Preparation: Sendable {
        case ready(WebPFrameLease)
        case busy
        case unavailable
    }

    struct Statistics: Sendable {
        let residentBytes: Int
        let peakResidentBytes: Int
        let frameCount: Int
        let leasedFrames: Int
        let decodedFrames: Int
        let cacheHits: Int
        let mainThreadDecodes: Int
        let frameRequests: Int
        let sourceCount: Int
    }

    private struct FrameKey: Hashable {
        let animationID: String
        let index: Int
        let size: WebPPixelSize
    }

    private struct FrameEntry {
        let id: UUID
        let image: CGImage
        let cost: Int
        var leases: Int
        var accessed: UInt64
    }

    private struct SourceEntry {
        let source: CGImageSource
        var accessed: UInt64
    }

    let byteLimit: Int
    private let sourceLimit = 3
    private var sources: [String: SourceEntry] = [:]
    private var frames: [FrameKey: FrameEntry] = [:]
    private var residentBytes = 0
    private var peakResidentBytes = 0
    private var sequence: UInt64 = 0
    private var decodedFrames = 0
    private var cacheHits = 0
    private var mainThreadDecodes = 0
    private var frameRequests = 0

    init(byteLimit: Int = 16 * 1024 * 1024) {
        self.byteLimit = max(0, byteLimit)
    }

    func animation(for data: Data) -> WebPAnimation? {
        guard !Task.isCancelled, !data.isEmpty, data.count <= 16 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "org.webmproject.webp" else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1, count <= 512,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              width * height <= 4 * 1024 * 1024 else { return nil }
        let durations = (0..<count).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            return Self.frameDuration(from: properties?[kCGImagePropertyWebPDictionary] as? [CFString: Any])
        }
        guard !Task.isCancelled else { return nil }
        let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        remember(source, id: id)
        return WebPAnimation(id: id, data: data, durations: durations, width: width, height: height)
    }

    nonisolated static func frameDuration(from properties: [CFString: Any]?) -> TimeInterval {
        let unclamped = (properties?[kCGImagePropertyWebPUnclampedDelayTime] as? NSNumber)?.doubleValue
        let clamped = (properties?[kCGImagePropertyWebPDelayTime] as? NSNumber)?.doubleValue
        let valid = [unclamped, clamped].compactMap { $0 }.first { $0.isFinite && $0 > 0.01 }
        return min(max(valid ?? (1.0 / 24.0), 0.01), 1.0)
    }

    func frame(for animation: WebPAnimation, index: Int, pixelSize: WebPPixelSize) -> WebPFrameLease? {
        if case let .ready(frame) = prepareFrame(for: animation, index: index, pixelSize: pixelSize) { return frame }
        return nil
    }

    func prepareFrame(for animation: WebPAnimation, index: Int, pixelSize: WebPPixelSize) -> Preparation {
        frameRequests += 1
        guard !Task.isCancelled, animation.durations.indices.contains(index) else { return .unavailable }
        let size = pixelSize.fitting(animation)
        let key = FrameKey(animationID: animation.id, index: index, size: size)
        sequence &+= 1
        if let cached = cachedLease(for: key) {
            return cached
        }
        // Leased frames are never evicted. If every byte is in use, the caller keeps
        // its current picture and retries later instead of oversubscribing memory.
        guard size.byteCost <= byteLimit else { return .unavailable }
        guard makeRoom(for: size.byteCost) else { return .busy }
        guard let source = source(for: animation) else { return .unavailable }
        guard !Task.isCancelled, let image = decodeFrameImage(from: source, index: index, size: size) else { return .unavailable }
        decodedFrames += 1
        if Thread.isMainThread { mainThreadDecodes += 1 }
        let cost = image.bytesPerRow * image.height
        // Account for the actual bitmap stride, not just width * height * four.
        guard cost <= size.byteCost else { return .unavailable }
        let entry = FrameEntry(id: UUID(), image: image, cost: cost, leases: 1, accessed: sequence)
        frames[key] = entry
        residentBytes += cost
        peakResidentBytes = max(peakResidentBytes, residentBytes)
        return .ready(lease(entry, key: key))
    }

    private func cachedLease(for key: FrameKey) -> Preparation? {
        guard var entry = frames[key] else { return nil }
        cacheHits += 1
        entry.leases += 1
        entry.accessed = sequence
        frames[key] = entry
        return .ready(lease(entry, key: key))
    }

    private func decodeFrameImage(from source: CGImageSource, index: Int, size: WebPPixelSize) -> CGImage? {
        autoreleasepool {
            guard let raw = CGImageSourceCreateImageAtIndex(source, index,
                      [kCGImageSourceShouldCache: false] as CFDictionary),
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: size.width, height: size.height,
                      bitsPerComponent: 8, bytesPerRow: size.bytesPerRow, space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(raw, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            return context.makeImage()
        }
    }

    func statistics() -> Statistics {
        Statistics(residentBytes: residentBytes, peakResidentBytes: peakResidentBytes,
                   frameCount: frames.count, leasedFrames: frames.values.filter { $0.leases > 0 }.count,
                   decodedFrames: decodedFrames, cacheHits: cacheHits,
                   mainThreadDecodes: mainThreadDecodes, frameRequests: frameRequests, sourceCount: sources.count)
    }

    func removeUnusedFrames() {
        for key in frames.keys where frames[key]?.leases == 0 {
            residentBytes -= frames.removeValue(forKey: key)?.cost ?? 0
        }
        sources.removeAll()
    }

    private func lease(_ entry: FrameEntry, key: FrameKey) -> WebPFrameLease {
        WebPFrameLease(image: entry.image, index: key.index, byteCost: entry.cost) { [weak self] in
            Task { await self?.release(key, id: entry.id) }
        }
    }

    private func release(_ key: FrameKey, id: UUID) {
        guard var entry = frames[key], entry.id == id else { return }
        entry.leases = max(0, entry.leases - 1)
        frames[key] = entry
    }

    private func makeRoom(for cost: Int) -> Bool {
        while residentBytes > byteLimit - cost {
            guard let key = frames.filter({ $0.value.leases == 0 })
                .min(by: { $0.value.accessed < $1.value.accessed })?.key else { return false }
            residentBytes -= frames.removeValue(forKey: key)?.cost ?? 0
        }
        return true
    }

    private func source(for animation: WebPAnimation) -> CGImageSource? {
        if var entry = sources[animation.id] {
            entry.accessed = sequence
            sources[animation.id] = entry
            return entry.source
        }
        guard let source = CGImageSourceCreateWithData(animation.data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        remember(source, id: animation.id)
        return source
    }

    private func remember(_ source: CGImageSource, id: String) {
        sequence &+= 1
        if sources[id] == nil, sources.count >= sourceLimit,
           let oldest = sources.min(by: { $0.value.accessed < $1.value.accessed })?.key {
            sources.removeValue(forKey: oldest)
        }
        sources[id] = SourceEntry(source: source, accessed: sequence)
    }
}
