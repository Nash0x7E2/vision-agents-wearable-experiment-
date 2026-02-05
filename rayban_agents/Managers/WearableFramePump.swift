//
//  WearableFramePump.swift
//  rayban_agents
//
//  Pumps wearable camera frames into an ExternalFrameSink at ~30 fps.
//

import CoreImage
import CoreVideo
import Foundation
import MWDATCamera
import StreamVideo
import UIKit
import Metal

enum WearableFramePump {
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Reuse one GPU-backed CIContext if possible
    private static let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        } else {
            return CIContext(options: [.useSoftwareRenderer: false])
        }
    }()

    private struct PixelPoolKey: Hashable { let width: Int; let height: Int }
    // Cache a pixel buffer pool per resolution
    private static var poolCache = [PixelPoolKey: CVPixelBufferPool]()

    private static func pool(for resolution: StreamingResolution) -> CVPixelBufferPool? {
        let width = Int(resolution.videoFrameSize.width)
        let height = Int(resolution.videoFrameSize.height)
        let key = PixelPoolKey(width: width, height: height)
        if let p = poolCache[key] { return p }
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        var p: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &p)
        if let created = p { poolCache[key] = created }
        return p
    }

    static func makePixelBuffer(from ciImage: CIImage, resolution: StreamingResolution) -> CVPixelBuffer? {
        autoreleasepool {
            let width = Int(resolution.videoFrameSize.width)
            let height = Int(resolution.videoFrameSize.height)
            guard let pool = pool(for: resolution) else { return nil }

            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
                return nil
            }

            // Scale with fill to avoid letterboxing; crop to exact size
            let sx = CGFloat(width) / ciImage.extent.width
            let sy = CGFloat(height) / ciImage.extent.height
            let scale = max(sx, sy)
            let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let x = (scaled.extent.width - CGFloat(width)) * 0.5
            let y = (scaled.extent.height - CGFloat(height)) * 0.5
            let cropped = scaled.cropped(to: CGRect(x: x, y: y, width: CGFloat(width), height: CGFloat(height)))

            ciContext.render(
                cropped,
                to: buffer,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                colorSpace: colorSpace
            )
            return buffer
        }
    }
}
