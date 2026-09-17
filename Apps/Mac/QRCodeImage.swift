import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders a pairing link as a QR code.
///
/// CoreImage emits one module per pixel, so the tiny output is scaled up with
/// nearest-neighbour sampling — interpolating would blur the module edges and
/// make the code harder for a phone to read.
enum QRCodeImage {
    static func make(from string: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        // Medium correction: survives a little glare without inflating the module
        // count, which keeps the code readable at the size shown on screen.
        filter.correctionLevel = "M"

        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }

        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
