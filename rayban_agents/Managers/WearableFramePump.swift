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

enum WearableFramePump {
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    static func makePixelBuffer(from ciImage: CIImage, resolution: StreamingResolution) -> CVPixelBuffer? {
        let targetWidth = Int(resolution.videoFrameSize.width)
        let targetHeight = Int(resolution.videoFrameSize.height)
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetWidth,
            targetHeight,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard let buffer = pixelBuffer else { return nil }
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let scaleX = CGFloat(targetWidth) / ciImage.extent.width
        let scaleY = CGFloat(targetHeight) / ciImage.extent.height
        let scale = min(scaleX, scaleY)
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let destBounds = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        ctx.render(scaledImage, to: buffer, bounds: destBounds, colorSpace: Self.colorSpace)
        return buffer
    }
}
