# Liveflow

Mac 上比 OBS 更轻、更原生、更适合 Apple Silicon 的直播推流器。

基于 **Swift + AppKit/SwiftUI + ScreenCaptureKit + AVFoundation + Metal + VideoToolbox + HaishinKit (RTMP)** 打造，像素全程保留在 GPU 与 `IOSurface`，极低 CPU/内存占用与超低延迟。

---

## 架构核心原则

1. **零内存拷贝像素链路**：
   - 屏幕捕获（ScreenCaptureKit）与摄像头（AVFoundation）均直接输出 `IOSurface` / `CVPixelBuffer`。
   - 通过 `CVMetalTextureCache` 映射为 Metal 纹理，CPU 绝不进行逐像素复制。
2. **纯 Metal 场景合成引擎**：
   - 多图层（屏幕、摄像头 PIP、测试画面、插件源）在单次 Command Buffer 中利用 Metal Shader 批量合成。
   - 画面不经过 NSView/CALayer 截图，直接离屏渲染为 1080p60 目标画幅。
3. **VideoToolbox 硬件编码**：
   - 直接调用 Apple 媒体引擎（Media Engine）编码 H.264，超低延迟无 B 帧直播流配置。
4. **抽象推流协议层**：
   - 核心层定义 `StreamOutput` 协议，现阶段由 HaishinKit 提供稳定的 RTMP/RTMPS 传输支持，未来可平滑升级/替换为 SRT 或自研传输层。

---

## 快速运行与测试

### 1. 自动化推流测试（End-to-End Verification）
本项目内置基于本地 RTMP 接收器的全链路自动化推流测试，无需注册任何外部直播平台即可直接验证推流功能：

```bash
./scripts/test_stream.sh
```

该脚本将：
1. 启动本地 RTMP 监听服务（端口 19350）；
2. 启动 Liveflow 推送 1080p60 硬件编码 H.264 视频与 AAC 音频；
3. 验证接收到的视频编码、分辨率、帧率及数据包完整性。

### 2. 构建并打包 macOS 原生应用 (`.app`)
```bash
./scripts/build_app.sh release
open build/Liveflow.app
```
生成物位于 `build/Liveflow.app`，已配置 Entitlements 与签名，双击即可直接运行！

### 3. 在 Xcode 中打开开发
由于本项目采用标准的 Swift Package Manager 结构，直接使用 Xcode 打开根目录即可：
```bash
open Package.swift
```
在 Xcode 中选择 `Liveflow` scheme 并按 `Cmd + R` 即可运行和调试。

---

## 核心组件结构

- **`Sources/Liveflow/Core/`**
  - [`VideoFrame.swift`](Sources/Liveflow/Core/VideoFrame.swift): 封装 `CVPixelBuffer` / `IOSurface` 与零拷贝 Metal 纹理生成。
  - [`VideoSource.swift`](Sources/Liveflow/Core/VideoSource.swift): 所有画面源遵循的基础协议。
  - [`StreamOutput.swift`](Sources/Liveflow/Core/StreamOutput.swift): 推流目标协议。
  - [`StreamStats.swift`](Sources/Liveflow/Core/StreamStats.swift): 实时推流帧率、码率与统计数据。
- **`Sources/Liveflow/Sources/`**
  - [`TestPatternSource.swift`](Sources/Liveflow/Sources/TestPatternSource.swift): 60fps 动态彩条与时间戳测试画面。
  - [`ScreenCaptureSource.swift`](Sources/Liveflow/Sources/ScreenCaptureSource.swift): ScreenCaptureKit 屏幕/窗口捕获。
  - [`CameraSource.swift`](Sources/Liveflow/Sources/CameraSource.swift): AVFoundation 高清摄像头采集。
- **`Sources/Liveflow/Rendering/`**
  - [`MetalSceneRenderer.swift`](Sources/Liveflow/Rendering/MetalSceneRenderer.swift): Metal 场景多图层渲染器。
  - [`Shaders.metal`](Sources/Liveflow/Rendering/Shaders.metal) / [`ShaderSource.swift`](Sources/Liveflow/Rendering/ShaderSource.swift): 顶点与片段着色器（RGBA / NV12）。
- **`Sources/Liveflow/Streaming/`**
  - [`VideoToolboxEncoder.swift`](Sources/Liveflow/Streaming/VideoToolboxEncoder.swift): Apple Silicon 硬件加速编码器。
  - [`RTMPStreamOutput.swift`](Sources/Liveflow/Streaming/RTMPStreamOutput.swift): RTMP/RTMPS 推流传输封装。
- **`Sources/Liveflow/Audio/`**
  - [`AudioEngine.swift`](Sources/Liveflow/Audio/AudioEngine.swift): CoreAudio / AVAudioEngine 麦克风采集与 VU 电平表。
- **`Sources/Liveflow/Engine/`**
  - [`StreamEngine.swift`](Sources/Liveflow/Engine/StreamEngine.swift): 调度中心，独立后台 60fps 渲染循环与状态管理。
- **`Sources/Liveflow/UI/`**
  - [`MainWindowView.swift`](Sources/Liveflow/UI/MainWindowView.swift): 包含状态栏、Metal 画布与控制底栏的主界面。
  - [`CanvasView.swift`](Sources/Liveflow/UI/CanvasView.swift): `MTKView` 零拷贝实时预览画布。
  - [`StreamControlsView.swift`](Sources/Liveflow/UI/StreamControlsView.swift): 画面源切换、音量表、推流地址及开始推流控制面板。
