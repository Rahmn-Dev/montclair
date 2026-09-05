import AppKit

guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let cropped = sourceCG.cropping(to: CGRect(x: 165, y: 145, width: 924, height: 924)),
      let context = CGContext(
        data: nil,
        width: 1024,
        height: 1024,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    fatalError("Could not prepare the Montclair icon")
}

context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.interpolationQuality = .high
let iconRect = CGRect(x: 82, y: 82, width: 860, height: 860)
context.addPath(CGPath(roundedRect: iconRect, cornerWidth: 184, cornerHeight: 184, transform: nil))
context.clip()
context.draw(cropped, in: iconRect)

guard let outputCG = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: outputCG).representation(using: .png, properties: [:]) else {
    fatalError("Could not render the Montclair icon")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
