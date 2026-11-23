import Foundation
import ImageIO
import QuartzCore
import SwiftUI

#if canImport(UIKit)
import UIKit

typealias WebPPlatformImageView = UIImageView

/// Plays the approved artwork using prepared frames, with a static first frame when paused.
struct AnimatedWebPImage: UIViewRepresentable {
    let data: Data
    let isPlaying: Bool
    let displaySize: CGSize
    var posterName: String?

    func makeUIView(context: Context) -> WebPFrameImageView {
        let view = WebPFrameImageView(frame: .zero)
        view.configure(data: data, isPlaying: isPlaying, displaySize: displaySize, posterName: posterName)
        return view
    }

    func updateUIView(_ uiView: WebPFrameImageView, context: Context) {
        uiView.configure(data: data, isPlaying: isPlaying, displaySize: displaySize, posterName: posterName)
    }

    static func dismantleUIView(_ uiView: WebPFrameImageView, coordinator: ()) { uiView.stop() }
}
#elseif canImport(AppKit)
import AppKit

typealias WebPPlatformImageView = NSImageView

struct AnimatedWebPImage: NSViewRepresentable {
    let data: Data
    let isPlaying: Bool
    let displaySize: CGSize
    var posterName: String?

    func makeNSView(context: Context) -> WebPFrameImageView {
        let view = WebPFrameImageView(frame: .zero)
        view.configure(data: data, isPlaying: isPlaying, displaySize: displaySize, posterName: posterName)
        return view
    }

    func updateNSView(_ nsView: WebPFrameImageView, context: Context) {
        nsView.configure(data: data, isPlaying: isPlaying, displaySize: displaySize, posterName: posterName)
    }

    static func dismantleNSView(_ nsView: WebPFrameImageView, coordinator: ()) { nsView.stop() }
}
#endif

extension AnimatedWebPImage {
    nonisolated static func frameDuration(from properties: [CFString: Any]?) -> CFTimeInterval {
        WebPFrameStore.frameDuration(from: properties)
    }

    nonisolated static func isAnimated(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "org.webmproject.webp" else { return false }
        return CGImageSourceGetCount(source) > 1
    }
}

/// UIKit and AppKit share the same preparation/lifetime rules. The main-thread clock only
/// chooses an authored frame index and assigns a ready bitmap. It never invokes ImageIO.
@MainActor
final class WebPFrameImageView: WebPPlatformImageView {
    private var sourceData: Data?
    private var animation: WebPAnimation?
    private var displaySize = CGSize.zero
    private var pixelSize: WebPPixelSize?
    private var currentPixelSize: WebPPixelSize?
    private var currentFrame: WebPFrameLease?
    private(set) var currentFrameIndex: Int?
    private var desiredFrameIndex = 0
    private var playbackStartedAt: CFTimeInterval?
    private var wantsPlayback = false
    private var explicitlyStopped = false
    private var frameUnavailable = false
    private var generation: UInt64 = 0
    private var preparationTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private let frameStore: WebPFrameStore
#if canImport(UIKit)
    private var displayLink: CADisplayLink?
#else
    private var timer: Timer?
#endif
    private var clockTarget: WebPClockTarget?

    override init(frame: CGRect) {
        frameStore = .shared
        super.init(frame: frame)
        setUpImageView()
    }

    init(frame: CGRect, frameStore: WebPFrameStore) {
        self.frameStore = frameStore
        super.init(frame: frame)
        setUpImageView()
    }

    required init?(coder: NSCoder) {
        frameStore = .shared
        super.init(coder: coder)
        setUpImageView()
    }

    isolated deinit {
        preparationTask?.cancel()
        frameTask?.cancel()
#if canImport(UIKit)
        displayLink?.invalidate()
#else
        timer?.invalidate()
#endif
    }

    private func setUpImageView() {
#if canImport(UIKit)
        contentMode = .scaleAspectFit
        backgroundColor = .clear
        isOpaque = false
        registerForTraitChanges([UITraitDisplayScale.self]) { (view: WebPFrameImageView, _: UITraitCollection) in
            view.updatePixelSize()
        }
#else
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
#endif
    }

#if canImport(UIKit)
    override var intrinsicContentSize: CGSize {
        // A named PNG can have a much larger intrinsic size than its SwiftUI frame.
        // Use the requested logical geometry for both the poster and prepared frames.
        guard displaySize.width.isFinite, displaySize.height.isFinite,
              displaySize.width > 0, displaySize.height > 0 else {
            return super.intrinsicContentSize
        }
        return displaySize
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        movedToWindow()
    }
#else
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        movedToWindow()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updatePixelSize()
    }
#endif

    private func movedToWindow() {
        if window == nil {
            pause()
        } else if !explicitlyStopped {
            updatePixelSize()
            prepareIfNeeded()
            requestFrame()
            start()
        }
    }

    func configure(data: Data, isPlaying: Bool, displaySize: CGSize, posterName: String? = nil) {
        let dataChanged = sourceData != data
        let motionChanged = wantsPlayback != isPlaying
        explicitlyStopped = false
        wantsPlayback = isPlaying
        if dataChanged {
            pause()
            sourceData = data
            animation = nil
            // The approved PNG is only an opening placeholder, never layered behind
            // transparent moving frames. No WebP frame is decoded on the UI executor.
#if canImport(UIKit)
            image = posterName.flatMap { UIImage(named: $0) }
#else
            image = posterName.flatMap { NSImage(named: $0)?.copy() as? NSImage }
            image?.size = displaySize
#endif
            currentFrame = nil
            currentFrameIndex = nil
            currentPixelSize = nil
            desiredFrameIndex = 0
        }
        let sizeChanged = self.displaySize != displaySize
        self.displaySize = displaySize
#if canImport(UIKit)
        if sizeChanged { invalidateIntrinsicContentSize() }
#endif
        updatePixelSize(force: sizeChanged)
        if motionChanged, !isPlaying {
            pause()
            desiredFrameIndex = 0
        }
        prepareIfNeeded()
        if !isPlaying { desiredFrameIndex = 0 }
        requestFrame()
        start()
    }

    func stop() {
        explicitlyStopped = true
        wantsPlayback = false
        pause()
    }

    private func updatePixelSize(force: Bool = false) {
#if canImport(UIKit)
        let scale = max(window?.screen.scale ?? traitCollection.displayScale, 1)
        let next = WebPPixelSize(displaySize: displaySize, scale: scale)
#else
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let next = WebPPixelSize(displaySize: displaySize, scale: scale, geometry: .logicalSize)
#endif
        guard force || next != pixelSize else { return }
        cancelPendingWork()
        pixelSize = next
        currentPixelSize = nil
        if next == nil {
            stopClock()
            image = nil
            currentFrame = nil
            currentFrameIndex = nil
        }
        prepareIfNeeded()
        requestFrame()
    }

    private func prepareIfNeeded() {
        guard !explicitlyStopped, pixelSize != nil, animation == nil,
              preparationTask == nil, let data = sourceData else { return }
        let revision = generation
        preparationTask = Task { [weak self, frameStore] in
            let prepared = await frameStore.animation(for: data)
            guard !Task.isCancelled, let self, self.generation == revision else { return }
            self.preparationTask = nil
            self.animation = prepared
            self.requestFrame()
        }
    }

    private func requestFrame() {
        guard !explicitlyStopped, !frameUnavailable, frameTask == nil, let animation, let pixelSize,
              currentFrameIndex != desiredFrameIndex || currentPixelSize != pixelSize else { return }
        let index = desiredFrameIndex
        let revision = generation
        frameTask = Task { [weak self, frameStore] in
            let result = await Self.fetchFrameWithRetry(
                frameStore: frameStore,
                target: (animation: animation, index: index, pixelSize: pixelSize),
                revision: revision,
                currentRevision: { [weak self] in self?.generation }
            )
            guard !Task.isCancelled, let self, self.generation == revision else { return }
            self.frameTask = nil
            guard case let .ready(frame) = result else {
                self.frameUnavailable = true
                self.stopClock()
                return
            }
            self.applyReadyFrame(frame, index: index, pixelSize: pixelSize)
        }
    }

    private static func fetchFrameWithRetry(
        frameStore: WebPFrameStore,
        target: (animation: WebPAnimation, index: Int, pixelSize: WebPPixelSize),
        revision: UInt64,
        currentRevision: () -> UInt64?
    ) async -> WebPFrameStore.Preparation {
        var result = await frameStore.prepareFrame(for: target.animation, index: target.index, pixelSize: target.pixelSize)
        while case .busy = result {
            guard !Task.isCancelled, currentRevision() == revision else { return .busy }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return .busy }
            result = await frameStore.prepareFrame(for: target.animation, index: target.index, pixelSize: target.pixelSize)
        }
        return result
    }

    private func applyReadyFrame(_ frame: WebPFrameLease, index: Int, pixelSize: WebPPixelSize) {
#if canImport(UIKit)
        self.image = UIImage(cgImage: frame.image,
                             scale: CGFloat(frame.image.width) / self.displaySize.width, orientation: .up)
#else
        self.image = NSImage(cgImage: frame.image, size: self.displaySize)
#endif
        self.currentFrame = frame
        self.currentFrameIndex = index
        self.currentPixelSize = pixelSize
        self.start()
        if self.desiredFrameIndex != index { self.requestFrame() }
    }

    private func start() {
        guard wantsPlayback, !explicitlyStopped, !frameUnavailable, window != nil,
              animation != nil, currentFrame != nil, !hasClock else { return }
        playbackStartedAt = CACurrentMediaTime()
        let target = WebPClockTarget(owner: self)
        clockTarget = target
#if canImport(UIKit)
        let link = CADisplayLink(target: target, selector: #selector(WebPClockTarget.tick(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
#else
        let timer = Timer(timeInterval: 1.0 / 30.0, target: target,
                          selector: #selector(WebPClockTarget.tick(_:)), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
#endif
    }

    private var hasClock: Bool {
#if canImport(UIKit)
        displayLink != nil
#else
        timer != nil
#endif
    }

    private func stopClock() {
#if canImport(UIKit)
        displayLink?.invalidate()
        displayLink = nil
#else
        timer?.invalidate()
        timer = nil
#endif
        clockTarget = nil
        playbackStartedAt = nil
    }

    private func pause() {
        stopClock()
        cancelPendingWork()
    }

    private func cancelPendingWork() {
        generation &+= 1
        frameUnavailable = false
        preparationTask?.cancel()
        preparationTask = nil
        frameTask?.cancel()
        frameTask = nil
    }

    fileprivate func advance(at now: CFTimeInterval) {
        guard wantsPlayback, window != nil, !explicitlyStopped,
              let animation, let playbackStartedAt else { return }
        desiredFrameIndex = animation.frameIndex(at: max(0, now - playbackStartedAt))
        requestFrame()
    }
}

@MainActor
private final class WebPClockTarget: NSObject {
    weak var owner: WebPFrameImageView?
    init(owner: WebPFrameImageView) { self.owner = owner }
#if canImport(UIKit)
    @objc func tick(_ displayLink: CADisplayLink) { owner?.advance(at: displayLink.timestamp) }
#else
    @objc func tick(_ timer: Timer) { owner?.advance(at: CACurrentMediaTime()) }
#endif
}
