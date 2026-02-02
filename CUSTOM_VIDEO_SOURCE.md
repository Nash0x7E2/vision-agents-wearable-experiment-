# Custom Video Source (Option C) – Fork/Patch Guide

To send **only** wearable video (no iPhone camera) over WebRTC, the Stream Video Swift SDK must use a custom video source fed by wearable frames instead of the device camera. The SDK does not expose this today; it can be added by forking and patching.

## Current behavior

- We join with `CallSettings(audioOn: true, videoOn: false)` then call `camera.enable()`. The SDK still uses the **device camera** as the frame source and runs our `VideoFilter` (wearable or black). So the pipeline is still camera-driven.
- To remove the iPhone camera entirely we need the SDK to use an **external** `RTCVideoSource` that we push wearable frames to.

## SDK extension points

The SDK already has the right building blocks:

1. **`VideoCapturerProviding`** (Sources/StreamVideo/WebRTC/VideoCapturing/VideoCapturerProviding.swift)  
   - Protocol with `buildCameraCapturer(source: RTCVideoSource, audioDeviceModule:) -> StreamVideoCapturing`.
   - `StreamVideoCapturer.broadcastCapturer(with: audioDeviceModule:)` uses `RTCVideoCapturer(delegate: videoSource)` and does **not** use the device camera; the app would push frames to `videoSource`.

2. **`LocalVideoMediaAdapter`** (Sources/StreamVideo/WebRTC/v2/PeerConnection/MediaAdapters/LocalMediaAdapters/LocalVideoMediaAdapter.swift)  
   - Takes `capturerFactory: VideoCapturerProviding` (default `StreamVideoCapturerFactory()`).  
   - If we pass a **custom** `VideoCapturerProviding` that returns a “broadcast-style” capturer (no camera, delegate = source), the adapter would use our source.

3. **Where the factory is created**  
   - The adapter is created from the WebRTC layer (e.g. `RTCPeerConnectionCoordinator` or related). The factory is currently fixed to `StreamVideoCapturerFactory()`. We need a way to inject a custom `VideoCapturerProviding` (e.g. from `VideoConfig` or `Environment`) when building the call/controller.

## Fork/patch steps

1. **Clone stream-video-swift locally**
   - Clone https://github.com/GetStream/stream-video-swift into a sibling directory (e.g. `../stream-video-swift`).
   - In the Xcode project, add a **local** Swift package reference to that path and depend on it instead of the remote package.

2. **Add a custom video capturer provider**
   - In the SDK, add a type (e.g. `WearableVideoCapturerProvider`) that conforms to `VideoCapturerProviding` and implements `buildCameraCapturer` by returning:
     - `StreamVideoCapturer.broadcastCapturer(with: source, audioDeviceModule: audioDeviceModule)`  
     so no device camera is used; the same `RTCVideoSource` is the delegate and will receive frames we push.
   - Alternatively, add a new static factory on `StreamVideoCapturer` (e.g. `externalSourceCapturer(with: audioDeviceModule:)`) that uses `RTCVideoCapturer(delegate: videoSource)` and expose the `RTCVideoSource` for the app to push frames.

3. **Plumb the custom provider into the call**
   - Extend `VideoConfig` (or the environment used to build the call controller) with an optional `customVideoCapturerProvider: VideoCapturerProviding?`.
   - Where `LocalVideoMediaAdapter` is created, use `videoConfig.customVideoCapturerProvider ?? StreamVideoCapturerFactory()` instead of always `StreamVideoCapturerFactory()`.
   - Ensure the same `RTCVideoSource` (or a handle to push frames) is reachable from the app, e.g. via a callback or a dedicated API that the app can call with `CVPixelBuffer`/`RTCVideoFrame` from the wearable pipeline.

4. **App side**
   - When creating `StreamVideo`, pass a `VideoConfig` that sets `customVideoCapturerProvider` to the wearable provider.
   - The wearable provider’s `RTCVideoSource` must be fed from `WearablesManager.latestFrame` (or equivalent) at ~30 fps, converting `CIImage`/`UIImage` to `RTCVideoFrame` and calling the appropriate method on the source (see StreamWebRTC / WebRTC API for pushing frames).
   - Join with `CallSettings(audioOn: true, videoOn: false)` and then “enable” video using the custom track (or the SDK’s existing enable path if it already uses the custom capturer when the provider is set).

## Audio

Wearable microphone is already routed via `AVAudioSession.setPreferredInput` to the Bluetooth HFP port in `StreamCallManager`. No SDK fork is required for audio.

## References

- Stream Video Swift: https://github.com/GetStream/stream-video-swift  
- `VideoCapturerProviding`, `StreamVideoCapturer`, `LocalVideoMediaAdapter` in the SDK checkout (e.g. under `SourcePackages/checkouts/stream-video-swift` after a build).
