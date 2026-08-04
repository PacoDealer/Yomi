import UIKit
import CoreImage
import SwiftUI

// MARK: - UIImage average color
//
// Backs the Continue hero's "ambient tint sampled from the cover" background
// (DESIGN_SYSTEM §9.2). CIAreaAverage collapses the whole image to one pixel.

extension UIImage {
    func averageColor() -> Color? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extentVector = CIVector(
            x: inputImage.extent.origin.x, y: inputImage.extent.origin.y,
            z: inputImage.extent.size.width, w: inputImage.extent.size.height
        )
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector
        ]), let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            outputImage, toBitmap: &bitmap, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )
        return Color(
            red: Double(bitmap[0]) / 255,
            green: Double(bitmap[1]) / 255,
            blue: Double(bitmap[2]) / 255
        )
    }
}
