import Cocoa
import ImageIO

@main
struct ClipboardImageReaderTest {
  static func main() throws {
    let board = NSPasteboard(name: .init("scrapnote-tests-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func png(_ width: Int, _ height: Int = 2) -> Data {
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      return bitmap.representation(using: .png, properties: [:])!
    }
    let original = png(13)
    let icon = png(3)
    let file = directory.appendingPathComponent("original.png")
    try original.write(to: file)
    board.clearContents()
    board.writeObjects([file as NSURL])
    board.setData(icon, forType: .png)
    assert(NSBitmapImageRep(data: ClipboardImageReader.pngData(from: board)!)!.pixelsWide == 13, "Finder original must win over icon")
    assert(FileManager.default.fileExists(atPath: file.path))
    board.clearContents()
    board.setData(original, forType: .png)
    assert(NSBitmapImageRep(data: ClipboardImageReader.pngData(from: board)!)!.pixelsWide == 13, "Screenshot PNG must still work")
    let text = directory.appendingPathComponent("document.txt")
    try Data("text".utf8).write(to: text)
    board.clearContents()
    board.writeObjects([text as NSURL])
    board.setData(icon, forType: .png)
    assert(ClipboardImageReader.pngData(from: board) == nil, "Non-image file must not paste its icon")

    let gray16 = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 17, pixelsHigh: 9,
      bitsPerSample: 16, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
      colorSpaceName: .deviceWhite, bytesPerRow: 0, bitsPerPixel: 0)!
    board.clearContents()
    board.setData(gray16.tiffRepresentation!, forType: .tiff)
    let normalized = NSBitmapImageRep(data: ClipboardImageReader.pngData(from: board)!)!
    assert(normalized.pixelsWide == 17 && normalized.pixelsHigh == 9)
    assert(normalized.bitsPerSample == 8 && normalized.samplesPerPixel == 4)

    let portrait = png(2, 13)
    board.clearContents()
    board.setData(portrait, forType: .png)
    let pastedPortrait = NSBitmapImageRep(data: ClipboardImageReader.pngData(from: board)!)!
    assert(pastedPortrait.pixelsWide == 2 && pastedPortrait.pixelsHigh == 13,
      "Tall images must remain tall; never infer rotation from their dimensions")

    // Camera JPEGs may store landscape pixels with a portrait display tag.
    // Converting to PNG must preserve the original displayed direction.
    for orientation in 1...8 {
      let encoded = NSMutableData()
      let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil)!
      CGImageDestinationAddImage(destination, NSBitmapImageRep(data: original)!.cgImage!,
        [kCGImagePropertyOrientation: orientation] as CFDictionary)
      assert(CGImageDestinationFinalize(destination))
      let photo = directory.appendingPathComponent("camera-\(orientation).jpg")
      try (encoded as Data).write(to: photo)
      board.clearContents()
      board.writeObjects([photo as NSURL])
      let pasted = NSBitmapImageRep(data: ClipboardImageReader.pngData(from: board)!)!
      let swapsAxes = orientation >= 5
      assert(pasted.pixelsWide == (swapsAxes ? 2 : 13)
        && pasted.pixelsHigh == (swapsAxes ? 13 : 2),
        "Clipboard conversion must preserve display orientation \(orientation)")
    }
    board.clearContents()
    board.setData(Data("not an image".utf8), forType: .png)
    assert(ClipboardImageReader.pngData(from: board) == nil)
    print("Clipboard image tests passed")
  }
}
