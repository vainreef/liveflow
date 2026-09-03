import Foundation
import CoreMedia
import CoreVideo
import Metal
import Combine
import QuartzCore
import RTMPHaishinKit
import AVFoundation

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
    public var streamOutput: StreamOutput
    public let targetFPS: Int

    public func setStreamOutput(_ output: StreamOutput) {
        lock.withLock {
            self.streamOutput = output
        }
    }

    public func sendAudio(buffer: AVAudioBuffer, when: AVAudioTime) {
        let output: StreamOutput = lock.withLock { self.streamOutput }
        output.sendAudio(buffer: buffer, when: when)
    }

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

    // Strictly bounded in-flight frame semaphore (max 2 frames in-flight between CPU, GPU, and VideoToolbox).
    private let inFlightSemaphore = DispatchSemaphore(value: 2)
    private var droppedRenderFrames: UInt64 = 0

    public var totalDroppedRenderFrames: UInt64 {
        lock.withLock { droppedRenderFrames }
    }

    public func setLive(isLive: Bool, encoder: VideoToolboxEncoder?) {
        lock.withLock {
            self._isLive = isLive
            self.videoEncoder = encoder
        }
        sceneRenderer.setExternalPixelBufferPool(encoder?.pixelBufferPool)
    }

    private func tickRender() {
        // Probe semaphore with zero wait. If all 2 slots are busy, drop this frame immediately to prevent latency backlog!
        let waitResult = inFlightSemaphore.wait(timeout: .now())
        if waitResult == .timedOut {
            lock.withLock { droppedRenderFrames += 1 }
            return
        }

        frameCount += 1
        let pts = CMTime(value: frameCount, timescale: CMTimeScale(targetFPS))

        let (items, live, encoder) = lock.withLock {
            (_sceneItems, _isLive, videoEncoder)
        }

        let didSubmit = sceneRenderer.renderOffscreenAsync(items: items, timestamp: pts) { [weak self] pixelBuffer, texture in
            guard let self = self else { return }
            defer {
                self.inFlightSemaphore.signal()
            }

            self.lock.withLock {
                self._latestPreviewTexture = texture
            }

            if live, let encoder = encoder {
                let duration = CMTime(value: 1, timescale: CMTimeScale(self.targetFPS))
                encoder.encode(pixelBuffer: pixelBuffer, presentationTimeStamp: pts, duration: duration)
            }
        }

        if !didSubmit {
            inFlightSemaphore.signal()
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
    @Published public var selectedItemID: UUID? = nil
    @Published public var audioPeakLevel: Float = 0.0
    @Published public var availableDisplays: [DisplayItem] = []
    @Published public var hasScreenPermission: Bool = true
    @Published public var lastErrorMessage: String? = nil

    @Published public var rtmpURL: String = ""
    @Published public var streamKey: String = ""
    @Published public var isDryRunTest: Bool = false

    public var isTestMode: Bool {
        rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public let canvasWidth: Int = 1920
    public let canvasHeight: Int = 1080
    public let targetFPS: Int = 60
    public let targetBitrateKbps: Int = 15000

    public let worker: RenderLoopWorker
    private var videoEncoder: VideoToolboxEncoder?
    private var streamOutput: StreamOutput
    private let audioEngine = AudioEngine()
    private var cancellables = Set<AnyCancellable>()
    private var streamingActivityToken: NSObjectProtocol?

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
        selectedItemID = item.id
        sceneItems.append(item)
        worker.setSceneItems(sceneItems)

        Task {
            try? await testPattern.start()
        }
    }

    private func setupAudio() {
        let worker = self.worker
        audioEngine.setOutputHandler { buffer, time in
            worker.sendAudio(buffer: buffer, when: time)
        }
        try? audioEngine.start()
    }

    private func startStatsMonitor() {
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isLive {
                    var currentStats = self.streamOutput.stats
                    currentStats.droppedFrames = Int(self.worker.totalDroppedRenderFrames)
                    self.stats = currentStats
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
        lastErrorMessage = nil

        let testMode = isTestMode
        isDryRunTest = testMode

        let targetOutput: StreamOutput = testMode ? DryRunStreamOutput() : RTMPStreamOutput()
        self.streamOutput = targetOutput
        self.worker.setStreamOutput(targetOutput)

        // 1. Prepare VideoToolbox Hardware Encoder
        let encoder = VideoToolboxEncoder(
            width: Int32(canvasWidth),
            height: Int32(canvasHeight),
            fps: Int32(targetFPS),
            bitRate: Int32(targetBitrateKbps * 1000)
        )
        encoder.setOutputHandler { [weak targetOutput] sampleBuffer in
            targetOutput?.sendVideo(sampleBuffer: sampleBuffer)
        }

        do {
            try encoder.prepare()
            self.videoEncoder = encoder

            // 2. Connect
            if testMode {
                try await targetOutput.connect(url: URL(string: "http://localhost")!, streamKey: nil)
            } else {
                let cleanURL = rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: cleanURL) else {
                    status = .error("Invalid RTMP URL format")
                    return
                }
                try await targetOutput.connect(url: url, streamKey: streamKey)
            }

            self.isLive = true
            self.status = .streaming
            self.worker.setLive(isLive: true, encoder: encoder)
            self.streamingActivityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "Liveflow 1080p60 Realtime Live Stream"
            )
            print("[StreamEngine] \(testMode ? "Pipeline self-check test" : "Live stream") started successfully!")
        } catch let error as RTMPConnection.Error {
            let message: String
            switch error {
            case .invalidState:
                message = "Invalid RTMP state. Please retry."
            case .unsupportedCommand(let cmd):
                message = "Cannot connect: Invalid RTMP URL '\(cmd)'. Please check Server URL."
            case .connectionTimedOut:
                message = "Connection timed out. Server unreachable."
            case .socketErrorOccurred(let sockErr):
                if let sockErr = sockErr {
                    message = "Cannot connect to RTMP server (\(sockErr.localizedDescription)). Ensure server is running."
                } else {
                    message = "Cannot connect to RTMP server (Connection refused). Ensure server is running."
                }
            case .requestTimedOut:
                message = "RTMP request timed out."
            case .requestFailed(let resp):
                message = "RTMP request rejected by server: \(resp.status?.description ?? "Failed"). Check stream key."
            }
            self.status = .error(message)
            self.videoEncoder?.invalidate()
            self.videoEncoder = nil
            self.worker.setLive(isLive: false, encoder: nil)
            print("[StreamEngine] Failed to start stream: \(message)")
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
        isDryRunTest = false
        status = .idle
        worker.setLive(isLive: false, encoder: nil)
        videoEncoder?.invalidate()
        videoEncoder = nil
        if let token = streamingActivityToken {
            ProcessInfo.processInfo.endActivity(token)
            streamingActivityToken = nil
        }
        await streamOutput.disconnect()
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
            lastErrorMessage = "Please grant Screen Recording permission in System Settings and try again."
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
                isEnabled: true,
                nativeWidth: display.width,
                nativeHeight: display.height
            )
            item.fitToCanvas(canvasWidth: canvasWidth, canvasHeight: canvasHeight)
            selectedItemID = item.id
            sceneItems.append(item)
            worker.setSceneItems(sceneItems)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Failed to start screen capture: \(error.localizedDescription)"
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
            if selectedItemID == id {
                selectedItemID = sceneItems.first?.id
            }
            worker.setSceneItems(sceneItems)
            await item.source.stop()
        }
    }

    // MARK: - Transform & Crop Controls
    public var selectedItem: SceneItem? {
        sceneItems.first(where: { $0.id == selectedItemID })
    }

    // MARK: - Undo / Redo & Clipboard Management
    public struct UndoAction: Sendable {
        public let itemId: UUID
        public let before: SceneItemTransformSnapshot
        public let after: SceneItemTransformSnapshot
    }

    @Published public private(set) var undoStack: [UndoAction] = []
    @Published public private(set) var redoStack: [UndoAction] = []
    @Published public private(set) var clipboardTransform: SceneItemTransformSnapshot?

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var canPasteTransform: Bool { clipboardTransform != nil }

    public func recordTransformChange(itemId: UUID, before: SceneItemTransformSnapshot, after: SceneItemTransformSnapshot) {
        guard before != after else { return }
        undoStack.append(UndoAction(itemId: itemId, before: before, after: after))
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    public func undo() {
        guard let action = undoStack.popLast() else { return }
        guard let item = sceneItems.first(where: { $0.id == action.itemId }) else { return }
        action.before.apply(to: item)
        redoStack.append(action)
        selectedItemID = item.id
        updateSceneItems()
    }

    public func redo() {
        guard let action = redoStack.popLast() else { return }
        guard let item = sceneItems.first(where: { $0.id == action.itemId }) else { return }
        action.after.apply(to: item)
        undoStack.append(action)
        selectedItemID = item.id
        updateSceneItems()
    }

    public func copySelectedTransform() {
        guard let item = selectedItem else { return }
        clipboardTransform = SceneItemTransformSnapshot(from: item)
    }

    public func pasteSelectedTransform() {
        guard let item = selectedItem, let snapshot = clipboardTransform else { return }
        let before = SceneItemTransformSnapshot(from: item)
        snapshot.apply(to: item)
        recordTransformChange(itemId: item.id, before: before, after: snapshot)
        updateSceneItems()
    }

    public func fitSelectedItem() {
        guard let item = selectedItem else { return }
        let before = SceneItemTransformSnapshot(from: item)
        item.fitToCanvas(canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        let after = SceneItemTransformSnapshot(from: item)
        recordTransformChange(itemId: item.id, before: before, after: after)
        updateSceneItems()
    }

    public func fillAndCropSelectedItem() {
        guard let item = selectedItem else { return }
        let before = SceneItemTransformSnapshot(from: item)
        item.fillAndCrop(canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        let after = SceneItemTransformSnapshot(from: item)
        recordTransformChange(itemId: item.id, before: before, after: after)
        updateSceneItems()
    }

    public func resetSelectedItem() {
        guard let item = selectedItem else { return }
        let before = SceneItemTransformSnapshot(from: item)
        item.resetTransform()
        let after = SceneItemTransformSnapshot(from: item)
        recordTransformChange(itemId: item.id, before: before, after: after)
        updateSceneItems()
    }

    public func moveSelectedItem(dx: CGFloat, dy: CGFloat) {
        guard let item = selectedItem else { return }
        let before = SceneItemTransformSnapshot(from: item)
        item.move(dx: dx, dy: dy)
        let after = SceneItemTransformSnapshot(from: item)
        recordTransformChange(itemId: item.id, before: before, after: after)
        updateSceneItems()
    }

    public func updateSceneItems() {
        worker.setSceneItems(sceneItems)
        objectWillChange.send()
    }
}
