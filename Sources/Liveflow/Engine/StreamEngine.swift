import Foundation
import CoreMedia
import CoreVideo
import Metal
import Combine
import QuartzCore

public enum StreamStatus: Equatable, Sendable {
    case idle
    case connecting
    case streaming
    case error(String)
}

/// Background render worker that executes the 60fps Metal scene composition and VideoToolbox encoding.
/// Never blocks or is blocked by the MainActor / UI thread.
public final class RenderLoopWorker: @unchecked Sendable {
    public let sceneRenderer: MetalSceneRenderer
    public let streamOutput: StreamOutput
    public let targetFPS: Int

    private let renderQueue = DispatchQueue(label: "com.liveflow.renderloop", qos: .userInteractive)
    private var renderTimer: DispatchSourceTimer?
    private var videoEncoder: VideoToolboxEncoder?

    private let lock = NSLock()
    private var _sceneItems: [SceneItem] = []
    private var _isLive: Bool = false
    private var _latestPreviewTexture: MTLTexture?
    private var frameCount: Int64 = 0

    public var isLive: Bool {
        lock.withLock { _isLive }
    }

    public var latestPreviewTexture: MTLTexture? {
        lock.withLock { _latestPreviewTexture }
    }

    public init(streamOutput: StreamOutput, width: Int = 1920, height: Int = 1080, targetFPS: Int = 60) {
        self.streamOutput = streamOutput
        self.targetFPS = targetFPS
        let device = MTLCreateSystemDefaultDevice()!
        self.sceneRenderer = MetalSceneRenderer(device: device, width: width, height: height)
    }

    public func setSceneItems(_ items: [SceneItem]) {
        lock.withLock {
            _sceneItems = items
        }
    }

    public func startRenderLoop() {
        lock.withLock {
            guard renderTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: renderQueue)
            let interval = 1.0 / Double(targetFPS)
            timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in
                self?.tickRender()
            }
            self.renderTimer = timer
            timer.resume()
        }
    }

    public func stopRenderLoop() {
        lock.withLock {
            renderTimer?.cancel()
            renderTimer = nil
        }
    }

    public func setLive(isLive: Bool, encoder: VideoToolboxEncoder?) {
        lock.withLock {
            self._isLive = isLive
            self.videoEncoder = encoder
        }
    }

    private func tickRender() {
        frameCount += 1
        let pts = CMTime(value: frameCount, timescale: CMTimeScale(targetFPS))

        let (items, live, encoder) = lock.withLock {
            (_sceneItems, _isLive, videoEncoder)
        }

        guard let (pixelBuffer, texture) = sceneRenderer.renderOffscreen(items: items, timestamp: pts) else {
            return
        }

        lock.withLock {
            _latestPreviewTexture = texture
        }

        if live, let encoder = encoder {
            let duration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            encoder.encode(pixelBuffer: pixelBuffer, presentationTimeStamp: pts, duration: duration)
        }
    }
}

/// Central coordinator managing UI state, Audio Engine, and Stream Broadcast.
@MainActor
public final class StreamEngine: ObservableObject {
    @Published public var status: StreamStatus = .idle
    @Published public var isLive: Bool = false
    @Published public var stats: StreamStats = StreamStats()
    @Published public var sceneItems: [SceneItem] = []
    @Published public var audioPeakLevel: Float = 0.0
    @Published public var availableDisplays: [DisplayItem] = []
    @Published public var hasScreenPermission: Bool = true
    @Published public var lastErrorMessage: String? = nil

    @Published public var rtmpURL: String = "rtmp://127.0.0.1:19350/live"
    @Published public var streamKey: String = "test"
    public let canvasWidth: Int = 1920
    public let canvasHeight: Int = 1080
    public let targetFPS: Int = 60
    public let targetBitrateKbps: Int = 15000

    public let worker: RenderLoopWorker
    private var videoEncoder: VideoToolboxEncoder?
    private let streamOutput: StreamOutput
    private let audioEngine = AudioEngine()
    private var cancellables = Set<AnyCancellable>()

    public var latestPreviewTexture: MTLTexture? {
        worker.latestPreviewTexture
    }

    public init(streamOutput: StreamOutput = RTMPStreamOutput()) {
        self.streamOutput = streamOutput
        self.worker = RenderLoopWorker(streamOutput: streamOutput, width: 1920, height: 1080, targetFPS: 60)

        setupDefaultScene()
        setupAudio()
        worker.startRenderLoop()
        startStatsMonitor()
        Task { [weak self] in
            await self?.refreshDisplays()
        }
    }

    private func setupDefaultScene() {
        let testPattern = TestPatternSource(width: 1920, height: 1080, fps: targetFPS)
        let item = SceneItem(
            name: "Test Pattern (Color Bars)",
            source: testPattern,
            rect: CGRect(x: 0, y: 0, width: 1, height: 1),
            opacity: 1.0,
            zIndex: 0,
            isEnabled: true
        )
        sceneItems.append(item)
        worker.setSceneItems(sceneItems)

        Task {
            try? await testPattern.start()
        }
    }

    private func setupAudio() {
        let output = self.streamOutput
        audioEngine.setOutputHandler { buffer, time in
            output.sendAudio(buffer: buffer, when: time)
        }
        try? audioEngine.start()
    }

    private func startStatsMonitor() {
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isLive {
                    self.stats = self.streamOutput.stats
                }
                let newPeak = self.audioEngine.peakLevel
                if abs(self.audioPeakLevel - newPeak) > 0.05 || (newPeak == 0.0 && self.audioPeakLevel != 0.0) {
                    self.audioPeakLevel = newPeak
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Stream Controls
    public func startStreaming() async {
        guard !isLive else { return }
        status = .connecting

        guard let url = URL(string: rtmpURL) else {
            status = .error("Invalid RTMP URL")
            return
        }

        // 1. Prepare VideoToolbox Hardware Encoder
        let encoder = VideoToolboxEncoder(
            width: Int32(canvasWidth),
            height: Int32(canvasHeight),
            fps: Int32(targetFPS),
            bitRate: Int32(targetBitrateKbps * 1000)
        )
        let output = self.streamOutput
        encoder.setOutputHandler { sampleBuffer in
            output.sendVideo(sampleBuffer: sampleBuffer)
        }

        do {
            try encoder.prepare()
            self.videoEncoder = encoder

            // 2. Connect to RTMP
            try await streamOutput.connect(url: url, streamKey: streamKey)

            self.isLive = true
            self.status = .streaming
            self.worker.setLive(isLive: true, encoder: encoder)
            print("[StreamEngine] Live streaming started successfully!")
        } catch {
            self.status = .error(error.localizedDescription)
            self.videoEncoder?.invalidate()
            self.videoEncoder = nil
            self.worker.setLive(isLive: false, encoder: nil)
            print("[StreamEngine] Failed to start stream: \(error)")
        }
    }

    public func stopStreaming() async {
        guard isLive else { return }
        print("[StreamEngine] Stopping live stream...")
        isLive = false
        worker.setLive(isLive: false, encoder: nil)
        videoEncoder?.invalidate()
        videoEncoder = nil
        await streamOutput.disconnect()
        status = .idle
        stats = StreamStats()
    }

    // MARK: - Scene & Display Management
    public func refreshDisplays() async {
        hasScreenPermission = PermissionHelper.hasScreenRecordingPermission
        guard hasScreenPermission else {
            availableDisplays = []
            return
        }
        do {
            availableDisplays = try await ScreenCaptureSource.getAvailableDisplays()
        } catch {
            print("[StreamEngine] Failed to enumerate displays: \(error)")
        }
    }

    public func addScreenCaptureSource(display: DisplayItem) async {
        if !PermissionHelper.hasScreenRecordingPermission {
            PermissionHelper.requestScreenRecordingPermission()
            PermissionHelper.openScreenRecordingSettings()
            lastErrorMessage = "请在系统设置中允许 Liveflow 屏幕录制权限，然后重新添加显示器。"
            return
        }

        do {
            let screen = ScreenCaptureSource(display: display.scDisplay, name: display.name)
            try await screen.start()

            // If default Test Pattern is the only item, replace it
            if sceneItems.count == 1 && sceneItems[0].source is TestPatternSource {
                let old = sceneItems.removeFirst()
                await old.source.stop()
            }

            let item = SceneItem(
                name: display.name,
                source: screen,
                rect: CGRect(x: 0, y: 0, width: 1, height: 1),
                opacity: 1.0,
                zIndex: sceneItems.count,
                isEnabled: true
            )
            sceneItems.append(item)
            worker.setSceneItems(sceneItems)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "启动屏幕捕获失败: \(error.localizedDescription)"
            print("[StreamEngine] addScreenCaptureSource error: \(error)")
        }
    }

    public func addTestPatternSource() async {
        let testPattern = TestPatternSource(width: 1920, height: 1080, fps: targetFPS)
        let item = SceneItem(
            name: "Test Pattern (Color Bars)",
            source: testPattern,
            rect: CGRect(x: 0, y: 0, width: 1, height: 1),
            opacity: 1.0,
            zIndex: sceneItems.count,
            isEnabled: true
        )
        sceneItems.append(item)
        worker.setSceneItems(sceneItems)
        try? await testPattern.start()
    }

    public func addCameraSource() async throws {
        let camera = CameraSource()
        try await camera.start()
        let item = SceneItem(
            name: "Camera (PIP)",
            source: camera,
            rect: CGRect(x: 0.65, y: 0.65, width: 0.32, height: 0.32),
            opacity: 1.0,
            zIndex: sceneItems.count + 1,
            isEnabled: true
        )
        sceneItems.append(item)
        worker.setSceneItems(sceneItems)
    }

    public func removeSceneItem(id: UUID) async {
        if let idx = sceneItems.firstIndex(where: { $0.id == id }) {
            let item = sceneItems.remove(at: idx)
            worker.setSceneItems(sceneItems)
            await item.source.stop()
        }
    }
}
