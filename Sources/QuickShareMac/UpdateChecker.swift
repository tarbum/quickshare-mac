import AppKit
import Foundation

final class UpdateChecker: ObservableObject {
  static let shared = UpdateChecker()

  static let repository = "tarbum/quickshare-mac"

  @Published private(set) var isChecking = false
  @Published private(set) var lastError: String?

  private struct Release: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let prerelease: Bool
    let draft: Bool

    enum CodingKeys: String, CodingKey {
      case tagName = "tag_name"
      case name, body
      case htmlURL = "html_url"
      case prerelease, draft
    }
  }

  private init() {}

  var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "0"
  }

  func checkForUpdates(manual: Bool) {
    guard !isChecking else { return }
    guard
      let url = URL(
        string: "https://api.github.com/repos/\(Self.repository)/releases/latest")
    else { return }

    isChecking = true
    lastError = nil

    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue(
      "QuickShareMac/\(currentVersion)", forHTTPHeaderField: "User-Agent")

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.isChecking = false

        if let error = error {
          self.finish(
            manual: manual,
            error: "Could not check for updates: \(error.localizedDescription)")
          return
        }

        guard let http = response as? HTTPURLResponse else {
          self.finish(manual: manual, error: "Invalid update response.")
          return
        }

        if http.statusCode == 404 {
          self.finish(
            manual: manual,
            error:
              "No published release was found for \(Self.repository).")
          return
        }
        if http.statusCode == 403 {
          self.finish(
            manual: manual,
            error: "GitHub rate limit reached. Try again later.")
          return
        }
        guard http.statusCode == 200, let data = data else {
          self.finish(
            manual: manual,
            error: "GitHub returned HTTP \(http.statusCode).")
          return
        }

        do {
          let release = try JSONDecoder().decode(Release.self, from: data)
          guard !release.prerelease, !release.draft else {
            self.finish(manual: manual, message: "You're up to date.")
            return
          }

          if Self.isNewer(release.tagName, than: self.currentVersion) {
            self.present(release)
          } else {
            self.finish(
              manual: manual,
              message: "Quick Share \(self.currentVersion) is the latest version.")
          }
        } catch {
          self.finish(
            manual: manual,
            error: "Could not read the GitHub release: \(error.localizedDescription)")
        }
      }
    }.resume()
  }

  private func present(_ release: Release) {
    NSApplication.shared.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "Quick Share update available"
    let title = release.name?.trimmingCharacters(in: .whitespacesAndNewlines)
    alert.informativeText =
      "Current version: \(currentVersion)\nLatest release: \(title?.isEmpty == false ? title! : release.tagName)\n\n"
      + Self.shortNotes(release.body)
    alert.addButton(withTitle: "Open Release Page")
    alert.addButton(withTitle: "Later")
    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.open(release.htmlURL)
    }
  }

  private func finish(manual: Bool, error: String) {
    lastError = error
    if manual {
      showAlert(title: "Update Check Failed", message: error)
    }
  }

  private func finish(manual: Bool, message: String) {
    if manual {
      showAlert(title: "Check for Updates", message: message)
    }
  }

  private func showAlert(title: String, message: String) {
    NSApplication.shared.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private static func isNewer(_ tag: String, than current: String) -> Bool {
    let remote = versionParts(tag)
    let local = versionParts(current)
    let count = max(remote.count, local.count)
    for index in 0..<count {
      let left = index < remote.count ? remote[index] : 0
      let right = index < local.count ? local[index] : 0
      if left != right { return left > right }
    }
    return false
  }

  private static func versionParts(_ version: String) -> [Int] {
    version
      .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
      .split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "+" })
      .map { part in
        let digits = part.prefix { $0.isNumber }
        return Int(digits) ?? 0
      }
  }

  private static func shortNotes(_ body: String?) -> String {
    guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines),
      !body.isEmpty
    else {
      return "Open the release page for details and the download."
    }
    let lines = body.split(separator: "\n").prefix(8).joined(separator: "\n")
    return String(lines.prefix(700))
  }
}
