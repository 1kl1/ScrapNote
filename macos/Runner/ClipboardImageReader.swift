import Cocoa
import ImageIO

enum ClipboardImageReader {
  static func pngData(from pasteboard: NSPasteboard) -> Data? {
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] ?? []
    if !urls.isEmpty {
      for url in urls {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url), let png = normalizedPNG(data) {
          return png
        }
      }
      // Finder publishes a file icon too; never use that as the photo.
      return nil
    }
    if let data = pasteboard.data(forType: .png), let png = normalizedPNG(data) {
      return png
    }
    if let data = pasteboard.data(forType: .tiff), let png = normalizedPNG(data) {
      return png
    }
    return nil
  }

  /// Flatten clipboard encodings (including 16-bit, grayscale and TIFF) into
  /// one 8-bit sRGB PNG with well-defined alpha for Flutter's image decoder.
  static func normalizedPNG(_ data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let normalized = context.makeImage() else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      output, "public.png" as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(destination, normalized, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }
}
