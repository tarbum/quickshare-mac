import AppKit

final class ServicesProvider: NSObject {
  static let shared = ServicesProvider()

  @objc func openFile(
    _ pasteboard: NSPasteboard,
    userData: String,
    error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    guard
      let urls = pasteboard.readObjects(
        forClasses: [NSURL.self], options: nil) as? [URL],
      !urls.isEmpty
    else {
      errorPointer.pointee = "No files were provided." as NSString
      return
    }

    pasteboard.clearContents()
    DispatchQueue.main.async {
      QuickShareService.shared.beginSendFromFinder(files: urls)
    }
  }
}
