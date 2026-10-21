import AppKit
import Foundation
import os

/// Central log sink.
///
/// The Nearby Connections core logs through absl `LOG()` / `VLOG()` directly to
/// stderr. When the app is launched by Finder or launchd, stderr is `/dev/null`,
/// so every diagnostic from the framework (including "Failed to find network"
/// and bandwidth-upgrade decisions) used to be discarded. `start()` redirects
/// stdout/stderr into a rotating file so those lines survive.
///
/// Per-transfer diagnostics also go to `os_log` (subsystem `com.quickshare.mac`)
/// so `log stream --process QuickShareMac` works without tailing the file.
enum Diagnostics {
  static let directory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/QuickShareMac", isDirectory: true)
  static let logURL = directory.appendingPathComponent("QuickShareMac.log")
  static let archivedLogURL = directory.appendingPathComponent("QuickShareMac.1.log")

  private static let maxLogBytes: UInt64 = 8 * 1024 * 1024
  private static let logger = Logger(subsystem: "com.quickshare.mac", category: "transfer")
  private static var started = false
  /// Write end of the log file, kept when stdout/stderr stay attached to a TTY.
  private static var fileDescriptor: Int32 = -1
  private static var redirected = false

  /// Call once, as early as possible in the launch sequence.
  static func start() {
    guard !started else { return }
    started = true

    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    rotateIfNeeded()

    let fd = open(logURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    guard fd >= 0 else { return }

    // When launched from a terminal (CLI test modes), keep the terminal wired
    // up so the caller still sees output; diagnostics are mirrored to the file
    // by `mirror(_:)`. Finder/launchd launches have no terminal, and there we
    // take over stdout/stderr so the framework's absl logs land in the file.
    if isatty(STDOUT_FILENO) == 1 {
      fileDescriptor = fd
    } else {
      dup2(fd, STDOUT_FILENO)
      dup2(fd, STDERR_FILENO)
      if fd > STDERR_FILENO { close(fd) }
      redirected = true
    }

    setvbuf(stdout, nil, _IOLBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    log("=== QuickShareMac \(version) (\(build)) started, macOS \(os) ===")
    log("=== log file: \(logURL.path) ===")
    let args = CommandLine.arguments.dropFirst().joined(separator: " ")
    if !args.isEmpty { log("=== args: \(args) ===") }
    TransferTuning.apply()
  }

  /// Timestamped, millisecond-resolution line. Goes to stderr (the log file),
  /// the unified log, and — when `verboseUI` is on — the Activity list.
  static func log(_ message: String, verboseUI: Bool = false) {
    let line = "\(timestamp()) [diag] \(message)"
    logger.debug("\(message, privacy: .public)")
    print(line)
    fflush(stdout)
    mirror(line)
    if verboseUI {
      QuickShareService.shared.appendToActivity(line)
    }
  }

  /// Writes a line straight to the log file when stdout is not redirected.
  /// `O_APPEND` keeps concurrent writers from interleaving mid-line.
  static func mirror(_ line: String) {
    guard !redirected, fileDescriptor >= 0 else { return }
    let bytes = Array((line + "\n").utf8)
    _ = bytes.withUnsafeBufferPointer { write(fileDescriptor, $0.baseAddress, $0.count) }
  }

  /// User-visible events from `QuickShareService.appendLog`, mirrored into the
  /// unified log so `log stream` shows them alongside framework logs.
  static func event(_ message: String) {
    logger.notice("\(message, privacy: .public)")
  }

  static func revealLog() {
    NSWorkspace.shared.activateFileViewerSelecting([logURL])
  }

  static func timestamp() -> String {
    formatter.string(from: Date())
  }

  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  private static func rotateIfNeeded() {
    let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path)
    let size = attributes?[.size] as? UInt64 ?? 0
    guard size > maxLogBytes else { return }
    try? FileManager.default.removeItem(at: archivedLogURL)
    try? FileManager.default.moveItem(at: logURL, to: archivedLogURL)
  }
}

/// Throttled throughput sampler for `Progress` objects.
final class ProgressSampler {
  private var last: (date: Date, bytes: Int64)?

  /// Returns the rate in MB/s, or `nil` when the sample was throttled.
  func sample(bytes: Int64, minInterval: TimeInterval = 1.0) -> Double? {
    let now = Date()
    if let last, now.timeIntervalSince(last.date) < minInterval { return nil }
    defer { self.last = (now, bytes) }
    guard let last else { return 0 }
    let elapsed = now.timeIntervalSince(last.date)
    guard elapsed > 0 else { return 0 }
    return Double(bytes - last.bytes) / elapsed / 1_048_576
  }
}

/// Human-readable byte count, e.g. "142.0 MB".
func formatBytes(_ count: Int64) -> String {
  guard count > 0 else { return "\(count) B" }
  let units = ["B", "KB", "MB", "GB"]
  var value = Double(count)
  var unit = 0
  while value >= 1024, unit < units.count - 1 {
    value /= 1024
    unit += 1
  }
  return String(format: "%.1f %@", value, units[unit])
}
