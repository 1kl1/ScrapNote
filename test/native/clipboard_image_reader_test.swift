import Cocoa

@main
struct ClipboardImageReaderTest {
  static func main() throws {
    let board = NSPasteboard(name: .init("scrapnote-tests-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func png(_ width: Int) -> Data {
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 2,
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
    assert(ClipboardImageReader.pngData(from: board) == original, "Finder original must win over icon")
    assert(FileManager.default.fileExists(atPath: file.path))
    board.clearContents()
    board.setData(original, forType: .png)
    assert(ClipboardImageReader.pngData(from: board) == original, "Screenshot PNG must still work")
    let text = directory.appendingPathComponent("document.txt")
    try Data("text".utf8).write(to: text)
    board.clearContents()
    board.writeObjects([text as NSURL])
    board.setData(icon, forType: .png)
    assert(ClipboardImageReader.pngData(from: board) == nil, "Non-image file must not paste its icon")
    print("Clipboard image tests passed")
  }
}
