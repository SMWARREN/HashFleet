import ImageIO
import SwiftUI
import Foundation

#if canImport(UIKit)
import UIKit

/// Plays a bundled animated WebP while retaining only the currently displayed frame.
/// The animation is optional so the approved static launch artwork remains the fallback.
struct AnimatedWebPImage: UIViewRepresentable {
    let data: Data
    let isPlaying: Bool
    let displaySize: CGSize

    nonisolated static func frameDuration(from properties: [CFString: Any]?) -> CFTimeInterval {
        let unclamped = (properties?[kCGImagePropertyWebPUnclampedDelayTime] as? NSNumber)?.doubleValue
        let clamped = (properties?[kCGImagePropertyWebPDelayTime] as? NSNumber)?.doubleValue
        let validDelay = [unclamped, clamped].compactMap { $0 }.first { $0 > 0.01 }
        return min(max(validDelay ?? (1.0 / 24.0), 0.01), 1.0)
    }

    nonisolated static func isAnimated(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              type as String == "org.webmproject.webp" else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    func makeUIView(context: Context) -> WebPFrameImageView {
        let view = WebPFrameImageView(frame: .zero)
        view.configure(data: data, isPlaying: isPlaying, displaySize: displaySize)
        return view
    }

    func updateUIView(_ uiView: WebPFrameImageView, context: Context) {
        uiView.configure(data: data, isPlaying: isPlaying, displaySize: displaySize)
    }

    static func dismantleUIView(_ uiView: WebPFrameImageView, coordinator: ()) {
        uiView.stop()
    }
}

@MainActor
final class WebPFrameImageView: UIImageView {
    private var sourceData: Data?
    private var source: CGImageSource?
    private var frameDurations: [CFTimeInterval] = []
    private var totalDuration: CFTimeInterval = 0
    private var currentFrameIndex: Int?
    private var playbackStartedAt: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private var displayLinkTarget: WebPDisplayLinkTarget?
    private var displaySize: CGSize?
    private var wantsPlayback = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFit
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentMode = .scaleAspectFit
        backgroundColor = .clear
        isOpaque = false
    }

    isolated deinit { displayLink?.invalidate() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { pause() } else if wantsPlayback { start() }
    }

    func configure(data: Data, isPlaying: Bool, displaySize: CGSize) {
        self.displaySize = displaySize
        if sourceData != data {
            pause()
            sourceData = data
            source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            loadFrameDurations()
            currentFrameIndex = nil
            showFrame(at: 0)
        }
        wantsPlayback = isPlaying
        if isPlaying, window != nil {
            start()
        } else {
            pause()
            if !isPlaying { showFrame(at: 0) }
        }
    }

    func stop() {
        wantsPlayback = false
        pause()
    }

    private func pause() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkTarget = nil
    }

    private func loadFrameDurations() {
        guard let source else {
            frameDurations = []
            totalDuration = 0
            return
        }
        frameDurations = (0..<CGImageSourceGetCount(source)).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let webP = properties?[kCGImagePropertyWebPDictionary] as? [CFString: Any]
            return AnimatedWebPImage.frameDuration(from: webP)
        }
        totalDuration = frameDurations.reduce(0, +)
    }

    private func start() {
        guard wantsPlayback, window != nil, displayLink == nil, frameDurations.count > 1, totalDuration > 0 else { return }
        let target = WebPDisplayLinkTarget(owner: self)
        let link = CADisplayLink(target: target, selector: #selector(WebPDisplayLinkTarget.tick(_:)))
        displayLinkTarget = target
        displayLink = link
        playbackStartedAt = CACurrentMediaTime()
        link.add(to: .main, forMode: .common)
    }

    fileprivate func advance(using link: CADisplayLink) {
        guard totalDuration > 0 else { return }
        var elapsed = (link.timestamp - playbackStartedAt).truncatingRemainder(dividingBy: totalDuration)
        var targetIndex = 0
        for (index, duration) in frameDurations.enumerated() {
            if elapsed < duration { targetIndex = index; break }
            elapsed -= duration
            targetIndex = index
        }
        showFrame(at: targetIndex)
    }

    private func showFrame(at index: Int) {
        guard let displaySize, displaySize.width > 0, displaySize.height > 0,
              index != currentFrameIndex, let source,
              index >= 0, index < CGImageSourceGetCount(source),
              let frame = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary) else { return }
        currentFrameIndex = index
        let imageScale = CGFloat(frame.width) / displaySize.width
        image = UIImage(cgImage: frame, scale: imageScale, orientation: .up)
    }
}

@MainActor
private final class WebPDisplayLinkTarget: NSObject {
    weak var owner: WebPFrameImageView?
    init(owner: WebPFrameImageView) { self.owner = owner }
    @objc func tick(_ displayLink: CADisplayLink) { owner?.advance(using: displayLink) }
}

#elseif canImport(AppKit)
import AppKit

/// AppKit-backed counterpart of the iOS frame player. ImageIO supplies real WebP frames and a
/// main-run-loop timer advances them; Reduce Motion and paused views still show the first frame.
struct AnimatedWebPImage: NSViewRepresentable {
    let data: Data
    let isPlaying: Bool
    let displaySize: CGSize

    nonisolated static func frameDuration(from properties: [CFString: Any]?) -> CFTimeInterval {
        let unclamped = (properties?[kCGImagePropertyWebPUnclampedDelayTime] as? NSNumber)?.doubleValue
        let clamped = (properties?[kCGImagePropertyWebPDelayTime] as? NSNumber)?.doubleValue
        let validDelay = [unclamped, clamped].compactMap { $0 }.first { $0 > 0.01 }
        return min(max(validDelay ?? (1.0 / 24.0), 0.01), 1.0)
    }

    nonisolated static func isAnimated(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              type as String == "org.webmproject.webp" else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    func makeNSView(context: Context) -> WebPFrameImageView {
        let view = WebPFrameImageView(frame: .zero)
        view.configure(data: data, isPlaying: isPlaying, displaySize: displaySize)
        return view
    }

    func updateNSView(_ nsView: WebPFrameImageView, context: Context) {
        nsView.configure(data: data, isPlaying: isPlaying, displaySize: displaySize)
    }

    static func dismantleNSView(_ nsView: WebPFrameImageView, coordinator: ()) {
        nsView.stop()
    }
}

@MainActor
final class WebPFrameImageView: NSImageView {
    private var sourceData: Data?
    private var source: CGImageSource?
    private var frameDurations: [CFTimeInterval] = []
    private var totalDuration: CFTimeInterval = 0
    private var currentFrameIndex: Int?
    private var playbackStartedAt: CFTimeInterval = 0
    private var timer: Timer?
    private var timerTarget: WebPTimerTarget?
    private var displaySize: CGSize?
    private var wantsPlayback = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    isolated deinit { timer?.invalidate() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { pause() } else if wantsPlayback { start() }
    }

    func configure(data: Data, isPlaying: Bool, displaySize: CGSize) {
        self.displaySize = displaySize
        if sourceData != data {
            pause()
            sourceData = data
            source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            loadFrameDurations()
            currentFrameIndex = nil
            showFrame(at: 0)
        }
        wantsPlayback = isPlaying
        if isPlaying, window != nil {
            start()
        } else {
            pause()
            if !isPlaying { showFrame(at: 0) }
        }
    }

    func stop() {
        wantsPlayback = false
        pause()
    }

    private func pause() {
        timer?.invalidate()
        timer = nil
        timerTarget = nil
    }

    private func loadFrameDurations() {
        guard let source else {
            frameDurations = []
            totalDuration = 0
            return
        }
        frameDurations = (0..<CGImageSourceGetCount(source)).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let webP = properties?[kCGImagePropertyWebPDictionary] as? [CFString: Any]
            return AnimatedWebPImage.frameDuration(from: webP)
        }
        totalDuration = frameDurations.reduce(0, +)
    }

    private func start() {
        guard wantsPlayback, window != nil, timer == nil, frameDurations.count > 1, totalDuration > 0 else { return }
        playbackStartedAt = ProcessInfo.processInfo.systemUptime
        let target = WebPTimerTarget(owner: self)
        let timer = Timer(timeInterval: 1.0 / 30.0, target: target,
                          selector: #selector(WebPTimerTarget.tick(_:)), userInfo: nil, repeats: true)
        timerTarget = target
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    fileprivate func advance() {
        guard totalDuration > 0 else { return }
        var elapsed = (ProcessInfo.processInfo.systemUptime - playbackStartedAt)
            .truncatingRemainder(dividingBy: totalDuration)
        var targetIndex = 0
        for (index, duration) in frameDurations.enumerated() {
            if elapsed < duration { targetIndex = index; break }
            elapsed -= duration
            targetIndex = index
        }
        showFrame(at: targetIndex)
    }

    private func showFrame(at index: Int) {
        guard let displaySize, displaySize.width > 0, displaySize.height > 0,
              index != currentFrameIndex, let source,
              index >= 0, index < CGImageSourceGetCount(source),
              let frame = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary) else { return }
        currentFrameIndex = index
        image = NSImage(cgImage: frame, size: displaySize)
    }
}

@MainActor
private final class WebPTimerTarget: NSObject {
    weak var owner: WebPFrameImageView?
    init(owner: WebPFrameImageView) { self.owner = owner }
    @objc func tick(_ timer: Timer) { owner?.advance() }
}
#endif
