import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private var vaultChannel: FlutterMethodChannel?
  private var imageClipboardChannel: FlutterMethodChannel?
  private var windowCloseGuardChannel: FlutterMethodChannel?
  private var editorCommandsChannel: FlutterMethodChannel?
  private var securityScopedVaultURL: URL?
  private var closeGuardEnabled = false
  private var closeRequestInFlight = false
  private var allowNextClose = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 960, height: 640)
    if windowFrame.width < 1200 || windowFrame.height < 720 {
      self.setContentSize(
        NSSize(
          width: max(windowFrame.width, 1200),
          height: max(windowFrame.height, 720)
        )
      )
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    configureVaultAccess(using: flutterViewController)
    configureImageClipboard(using: flutterViewController)
    configureWindowCloseGuard(using: flutterViewController)
    configureEditorCommands(using: flutterViewController)
    configureEditorMenu()
    delegate = self

    super.awakeFromNib()
  }

  deinit {
    securityScopedVaultURL?.stopAccessingSecurityScopedResource()
  }

  private func configureVaultAccess(using controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "scrapnote/vault_access",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "window_unavailable", message: "The app window is unavailable.", details: nil))
        return
      }

      switch call.method {
      case "selectDirectory":
        self.selectVault(result: result)
      case "restoreDirectory":
        self.restoreVault(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    vaultChannel = channel
  }

  private func configureImageClipboard(using controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "scrapnote/image_clipboard",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "window_unavailable", message: "The app window is unavailable.", details: nil))
        return
      }

      guard call.method == "readImagePath" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.readClipboardImage(result: result)
    }

    imageClipboardChannel = channel
  }

  private func configureWindowCloseGuard(using controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "scrapnote/window_close_guard",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "window_unavailable", message: "The app window is unavailable.", details: nil))
        return
      }

      guard call.method == "setEnabled", let enabled = call.arguments as? Bool else {
        if call.method == "setEnabled" {
          result(FlutterError(code: "invalid_arguments", message: "setEnabled requires a Boolean.", details: nil))
        } else {
          result(FlutterMethodNotImplemented)
        }
        return
      }

      self.closeGuardEnabled = enabled
      result(nil)
    }

    windowCloseGuardChannel = channel
  }

  private func configureEditorCommands(using controller: FlutterViewController) {
    editorCommandsChannel = FlutterMethodChannel(
      name: "scrapnote/editor_commands",
      binaryMessenger: controller.engine.binaryMessenger
    )
  }

  private func configureEditorMenu() {
    guard let mainMenu = NSApp.mainMenu,
          mainMenu.item(withTitle: "File") == nil
    else {
      return
    }

    let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    let fileMenu = NSMenu(title: "File")

    let newItem = NSMenuItem(
      title: "New Document",
      action: #selector(newEditorDocument(_:)),
      keyEquivalent: "n"
    )
    newItem.target = self
    fileMenu.addItem(newItem)

    let closeItem = NSMenuItem(
      title: "Close Editor",
      action: #selector(closeEditorDocument(_:)),
      keyEquivalent: "w"
    )
    closeItem.target = self
    fileMenu.addItem(closeItem)
    fileMenu.addItem(.separator())

    let saveItem = NSMenuItem(
      title: "Save",
      action: #selector(saveEditorDocument(_:)),
      keyEquivalent: "s"
    )
    saveItem.target = self
    fileMenu.addItem(saveItem)

    fileItem.submenu = fileMenu
    mainMenu.insertItem(fileItem, at: min(1, mainMenu.items.count))
  }

  @objc private func newEditorDocument(_ sender: Any?) {
    editorCommandsChannel?.invokeMethod("newDocumentRequested", arguments: nil)
  }

  @objc private func saveEditorDocument(_ sender: Any?) {
    editorCommandsChannel?.invokeMethod("saveRequested", arguments: nil)
  }

  @objc private func closeEditorDocument(_ sender: Any?) {
    editorCommandsChannel?.invokeMethod("closeDocumentRequested", arguments: nil)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if allowNextClose {
      allowNextClose = false
      return true
    }
    guard closeGuardEnabled else {
      return true
    }
    guard !closeRequestInFlight, let channel = windowCloseGuardChannel else {
      return false
    }

    closeRequestInFlight = true
    channel.invokeMethod("closeRequested", arguments: nil) { [weak self] response in
      guard let self else {
        return
      }
      self.closeRequestInFlight = false
      guard self.closeGuardEnabled, response as? Bool == true else {
        return
      }
      DispatchQueue.main.async {
        self.allowNextClose = true
        self.performClose(nil)
      }
    }
    return false
  }

  private func readClipboardImage(result: @escaping FlutterResult) {
    let pngData = ClipboardImageReader.pngData(from: .general)

    guard let pngData else {
      result(nil)
      return
    }

    do {
      let temporaryRoot = URL(
        fileURLWithPath: NSTemporaryDirectory(),
        isDirectory: true
      ).appendingPathComponent("scrapnote-paste", isDirectory: true)
      try FileManager.default.createDirectory(
        at: temporaryRoot,
        withIntermediateDirectories: true,
        attributes: nil
      )

      let imageURL = temporaryRoot
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("png")
      try pngData.write(to: imageURL, options: .atomic)
      result(imageURL.path)
    } catch {
      result(
        FlutterError(
          code: "clipboard_write_failed",
          message: "클립보드 이미지를 임시 파일로 저장하지 못했습니다.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func selectVault(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.title = "Scrapnote Vault 선택"
    panel.prompt = "이 폴더 사용"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false

    guard panel.runModal() == .OK, let url = panel.url else {
      result(nil)
      return
    }

    do {
      let bookmark = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      UserDefaults.standard.set(bookmark, forKey: "scrapnote.vaultBookmark")
      beginAccessing(url)
      result(url.path)
    } catch {
      result(
        FlutterError(
          code: "bookmark_create_failed",
          message: "Vault 접근 권한을 저장하지 못했습니다.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func restoreVault(result: @escaping FlutterResult) {
    guard let bookmark = UserDefaults.standard.data(forKey: "scrapnote.vaultBookmark") else {
      result(nil)
      return
    }

    do {
      var stale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )

      guard FileManager.default.fileExists(atPath: url.path) else {
        result(nil)
        return
      }

      beginAccessing(url)
      if stale {
        let refreshed = try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        UserDefaults.standard.set(refreshed, forKey: "scrapnote.vaultBookmark")
      }
      result(url.path)
    } catch {
      result(
        FlutterError(
          code: "bookmark_restore_failed",
          message: "저장된 Vault 접근 권한을 복원하지 못했습니다.",
          details: error.localizedDescription
        )
      )
    }
  }

  private func beginAccessing(_ url: URL) {
    securityScopedVaultURL?.stopAccessingSecurityScopedResource()
    _ = url.startAccessingSecurityScopedResource()
    securityScopedVaultURL = url
  }
}
