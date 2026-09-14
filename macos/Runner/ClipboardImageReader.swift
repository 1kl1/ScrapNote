import Cocoa

enum ClipboardImageReader {
  static func pngData(from pasteboard: NSPasteboard) -> Data? {
    // Finder also publishes an image of the file icon. Read the original file
    // before any rendered pasteboard representation.
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] ?? []
    if !urls.isEmpty {
      for url in urls {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let bitmap = NSBitmapImageRep(data: data) else { continue }
        if url.pathExtension.lowercased() == "png" { return data }
        if let png = bitmap.representation(using: .png, properties: [:]) {
          return png
        }
      }
      // A copied non-image file must not become its Finder icon.
      return nil
    }
    if let png = pasteboard.data(forType: .png),
       NSBitmapImageRep(data: png) != nil {
      return png
    }
    if let image = NSImage(pasteboard: pasteboard),
       let tiff = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff) {
      return bitmap.representation(using: .png, properties: [:])
    }
    return nil
  }
}
