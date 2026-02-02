//
//  WearablesManager.swift
//  rayban_agents
//
//  Manages Meta Wearables SDK integration including device registration,
//  camera streaming, and frame buffering for video calls.
//

import Foundation
import SwiftUI
import MWDATCore
import MWDATCamera

@Observable
final class WearablesManager {
    
    // MARK: - Published State
    
    private(set) var registrationState: RegistrationState = .notRegistered
    private(set) var devices: [Device] = []
    private(set) var streamState: StreamSessionState = .stopped
    private(set) var cameraPermissionStatus: PermissionStatus = .denied
    private(set) var latestFrame: UIImage?
    private(set) var isStreaming = false
    
    // MARK: - Private Properties
    
    private var streamSession: StreamSession?
    private var stateToken: ListenerToken?
    private var frameToken: ListenerToken?
    private var registrationTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    
    var isRegistered: Bool {
        registrationState == .registered
    }
    
    var hasConnectedDevice: Bool {
        !devices.isEmpty
    }
    
    var latestFrameAsCIImage: CIImage? {
        guard let uiImage = latestFrame, let cgImage = uiImage.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
    }
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Configuration
    
    func configure() {
        do {
            try Wearables.configure()
            observeRegistrationState()
            observeDevices()
        } catch {
            print("Failed to configure Wearables SDK: \(error)")
        }
    }
    
    // MARK: - Registration
    
    func startRegistration() {
        do {
            try Wearables.shared.startRegistration()
        } catch {
            print("Failed to start registration: \(error)")
        }
    }
    
    func startUnregistration() {
        do {
            try Wearables.shared.startUnregistration()
        } catch {
            print("Failed to start unregistration: \(error)")
        }
    }
    
    func handleCallback(url: URL) async {
        do {
            _ = try await Wearables.shared.handleUrl(url)
        } catch {
            print("Failed to handle callback URL: \(error)")
        }
    }
    
    // MARK: - Permissions
    
    func checkCameraPermission() async {
        do {
            cameraPermissionStatus = try await Wearables.shared.checkPermissionStatus(.camera)
        } catch {
            print("Failed to check camera permission: \(error)")
            cameraPermissionStatus = .denied
        }
    }
    
    func requestCameraPermission() async {
        do {
            cameraPermissionStatus = try await Wearables.shared.requestPermission(.camera)
        } catch {
            print("Failed to request camera permission: \(error)")
            cameraPermissionStatus = .denied
        }
    }
    
    // MARK: - Camera Streaming
    
    func startCameraStream() async {
        guard streamSession == nil else {
            print("Stream session already exists")
            return
        }
        
        let deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .low,
            frameRate: 24
        )
        
        let session = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)
        streamSession = session
        
        stateToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                self?.streamState = state
                self?.isStreaming = (state == .streaming)
            }
        }
        
        frameToken = session.videoFramePublisher.listen { [weak self] frame in
            guard let image = frame.makeUIImage() else { return }
            Task { @MainActor in
                self?.latestFrame = image
            }
        }
        
        await session.start()
    }
    
    func stopCameraStream() async {
        guard let session = streamSession else { return }
        
        await session.stop()
        
        stateToken = nil
        frameToken = nil
        streamSession = nil
        isStreaming = false
        latestFrame = nil
    }
    
    func capturePhoto() {
        streamSession?.capturePhoto(format: .jpeg)
    }
    
    // MARK: - Private Methods
    
    private func observeRegistrationState() {
        registrationTask?.cancel()
        registrationTask = Task {
            for await state in Wearables.shared.registrationStateStream() {
                await MainActor.run {
                    self.registrationState = state
                }
            }
        }
    }
    
    private func observeDevices() {
        devicesTask?.cancel()
        devicesTask = Task {
            for await deviceList in Wearables.shared.devicesStream() {
                await MainActor.run {
                    self.devices = deviceList
                }
            }
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        registrationTask?.cancel()
        devicesTask?.cancel()
        stateToken = nil
        frameToken = nil
        streamSession = nil
    }
}
