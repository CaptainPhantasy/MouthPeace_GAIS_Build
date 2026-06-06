import CoreGraphics
import Darwin
import Foundation

struct TerminalSessionCandidate: Equatable {
   let label: String
   let processName: String
   let parentProcessID: Int32
   let transport: String
   let terminalApplication: String
   let terminalApplicationVersion: String?
   let terminalApplicationProcessID: Int32?
   let terminalSessionIdentifier: String?
   let terminalPaneIdentifier: String?
   let agentTopBarText: String?
   let clientName: String?
   let clientVersion: String?

   static func detectStdioClient() -> TerminalSessionCandidate {
      let pid = getppid()
      let process = processName(for: pid) ?? "terminal"
      let terminal = terminalApplicationContext(parentProcessID: pid, processName: process)
      let label =
         terminal.agentTopBarText.map { "\(terminal.name) · \($0)" }
         ?? "\(terminal.name) · \(process)"
      return TerminalSessionCandidate(
         label: label,
         processName: process,
         parentProcessID: pid,
         transport: "stdio",
         terminalApplication: terminal.name,
         terminalApplicationVersion: terminal.version,
         terminalApplicationProcessID: terminal.processID,
         terminalSessionIdentifier: terminal.sessionIdentifier,
         terminalPaneIdentifier: terminal.paneIdentifier,
         agentTopBarText: terminal.agentTopBarText,
         clientName: nil,
         clientVersion: nil)
   }

   func merged(withInitializeParams params: [String: Any]) -> TerminalSessionCandidate? {
      guard let clientInfo = params["clientInfo"] as? [String: Any] else { return nil }
      let name = Self.clean(clientInfo["name"] as? String)
      let version = Self.clean(clientInfo["version"] as? String)
      guard name != nil || version != nil else { return nil }
      let displayName = name ?? clientName ?? processName
      let label =
         agentTopBarText.map { "\(terminalApplication) · \($0)" }
         ?? "\(terminalApplication) · \(displayName)"
      return TerminalSessionCandidate(
         label: label,
         processName: processName,
         parentProcessID: parentProcessID,
         transport: transport,
         terminalApplication: terminalApplication,
         terminalApplicationVersion: terminalApplicationVersion,
         terminalApplicationProcessID: terminalApplicationProcessID,
         terminalSessionIdentifier: terminalSessionIdentifier,
         terminalPaneIdentifier: terminalPaneIdentifier,
         agentTopBarText: agentTopBarText,
         clientName: name ?? clientName,
         clientVersion: version ?? clientVersion)
   }

   private struct ProcessSnapshot {
      let pid: pid_t
      let parentPID: pid_t
      let name: String
   }

   private static func terminalApplicationContext(parentProcessID: pid_t, processName: String)
      -> (
         name: String, version: String?, processID: pid_t?, sessionIdentifier: String?,
         paneIdentifier: String?, agentTopBarText: String?
      )
   {
      let env = ProcessInfo.processInfo.environment
      let ancestry = processAncestry(startingAt: parentProcessID)
      let terminalProcess = ancestry.first { isTerminalProcessName($0.name) }
      let rawProgram =
         clean(env["TERM_PROGRAM"])
         ?? clean(env["LC_TERMINAL"])
         ?? clean(env["__CFBundleIdentifier"])
         ?? terminalProcess?.name
         ?? processName
      let name = normalizeTerminalApplication(rawProgram)
      let version = clean(env["TERM_PROGRAM_VERSION"]) ?? clean(env["LC_TERMINAL_VERSION"])
      let sessionIdentifier =
         clean(env["TERM_SESSION_ID"])
         ?? clean(env["ITERM_SESSION_ID"])
         ?? clean(env["WT_SESSION"])
      let paneIdentifier =
         clean(env["WEZTERM_PANE"])
         ?? clean(env["KITTY_WINDOW_ID"])
         ?? clean(env["VSCODE_INJECTION"])
      let processID = terminalProcess?.pid
      let agentTopBarText =
         clean(env["MOUTHPEACE_AGENT_TOP_BAR_TEXT"])
         ?? terminalWindowTitle(processID: processID, ownerName: name)
         ?? clean(env["WINDOW_TITLE"])
         ?? clean(env["TERM_WINDOW_TITLE"])
      return (name, version, processID, sessionIdentifier, paneIdentifier, agentTopBarText)
   }

   private static func normalizeTerminalApplication(_ raw: String) -> String {
      let lower = raw.lowercased()
      if lower == "apple_terminal" || lower == "com.apple.terminal" {
         return "Terminal"
      }
      if lower == "iterm.app" || lower == "iterm2" || lower == "com.googlecode.iterm2" {
         return "iTerm2"
      }
      if lower.contains("wezterm") {
         return "WezTerm"
      }
      if lower.contains("ghostty") {
         return "Ghostty"
      }
      if lower.contains("kitty") {
         return "Kitty"
      }
      if lower.contains("warp") {
         return "Warp"
      }
      if lower.contains("alacritty") {
         return "Alacritty"
      }
      if lower.contains("cursor") {
         return "Cursor"
      }
      if lower.contains("vscode") || lower.contains("visual-studio-code") || lower == "code" {
         return "VS Code"
      }
      if raw.hasSuffix(".app") {
         return String(raw.dropLast(4))
      }
      return raw
   }

   private static func isTerminalProcessName(_ name: String) -> Bool {
      let lower = name.lowercased()
      return lower == "terminal"
         || lower.contains("iterm")
         || lower.contains("wezterm")
         || lower.contains("ghostty")
         || lower.contains("kitty")
         || lower.contains("warp")
         || lower.contains("alacritty")
         || lower.contains("tabby")
         || lower.contains("hyper")
         || lower == "code"
         || lower.contains("visual studio code")
         || lower.contains("cursor")
   }

   private static func processAncestry(startingAt pid: pid_t) -> [ProcessSnapshot] {
      var snapshots: [ProcessSnapshot] = []
      var current = pid
      var seen = Set<pid_t>()
      while current > 1 && current != getpid() && !seen.contains(current) {
         seen.insert(current)
         guard let snapshot = processSnapshot(for: current) else { break }
         snapshots.append(snapshot)
         current = snapshot.parentPID
      }
      return snapshots
   }

   private static func processSnapshot(for pid: pid_t) -> ProcessSnapshot? {
      var info = proc_bsdinfo()
      let expectedSize = MemoryLayout<proc_bsdinfo>.stride
      let actualSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(expectedSize))
      guard actualSize == Int32(expectedSize) else { return nil }
      return ProcessSnapshot(
         pid: pid,
         parentPID: pid_t(info.pbi_ppid),
         name: processName(for: pid) ?? "pid \(pid)")
   }

   private static func terminalWindowTitle(processID: pid_t?, ownerName: String) -> String? {
      guard
         let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
      else {
         return nil
      }
      for window in windows {
         if let layer = integer(window[kCGWindowLayer as String]), layer != 0 {
            continue
         }
         if let processID {
            guard integer(window[kCGWindowOwnerPID as String]) == Int(processID) else { continue }
         } else {
            let owner = clean(window[kCGWindowOwnerName as String] as? String)
            guard owner.map({ normalizeTerminalApplication($0) == ownerName }) ?? false else {
               continue
            }
         }
         if let title = clean(window[kCGWindowName as String] as? String) {
            return title
         }
      }
      return nil
   }

   private static func integer(_ value: Any?) -> Int? {
      if let number = value as? NSNumber { return number.intValue }
      if let int = value as? Int { return int }
      return nil
   }

   private static func processName(for pid: pid_t) -> String? {
      var buffer = [CChar](repeating: 0, count: 256)
      let length = proc_name(pid, &buffer, UInt32(buffer.count))
      guard length > 0 else { return nil }
      return String(cString: buffer)
   }

   private static func clean(_ value: String?) -> String? {
      guard let value else { return nil }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
   }
}

struct TerminalSessionColorSpec: Equatable {
   let name: String
   let hex: String
   let hueDegrees: Double
}

enum TerminalSessionState: String {
   case connected
   case disconnected
}

enum TerminalSessionPermissionState: String {
   case approved
   case killed
}

struct TerminalSession: Identifiable, Equatable {
   let id: Int
   let channelId: String
   var label: String
   var processName: String
   var parentProcessID: Int32
   var transport: String
   var terminalApplication: String
   var terminalApplicationVersion: String?
   var terminalApplicationProcessID: Int32?
   var terminalSessionIdentifier: String?
   var terminalPaneIdentifier: String?
   var agentTopBarText: String?
   var clientName: String?
   var clientVersion: String?
   let colorName: String
   let colorHex: String
   let connectedAt: Date
   var state: TerminalSessionState
   var permissionState: TerminalSessionPermissionState
   var receivesSignal: Bool

   var displayIdentifier: String {
      if let agentTopBarText {
         return "\(terminalApplication) · \(agentTopBarText)"
      }
      if let clientName {
         return "\(terminalApplication) · \(clientName)"
      }
      return "\(terminalApplication) · \(processName)"
   }

   var sessionHeader: String {
      var parts = [
         "Echo session #\(id)",
         "Terminal: \(terminalApplication)",
         "Channel \(channelId)",
      ]
      if let agentTopBarText { parts.append("Agent top bar: \(agentTopBarText)") }
      if let terminalApplicationVersion {
         parts.append("Terminal version: \(terminalApplicationVersion)")
      }
      if let terminalApplicationProcessID {
         parts.append("terminal pid \(terminalApplicationProcessID)")
      }
      if let clientName { parts.append(clientName) }
      parts.append(transport)
      parts.append("client pid \(parentProcessID)")
      if let terminalSessionIdentifier { parts.append("session \(terminalSessionIdentifier)") }
      if let terminalPaneIdentifier { parts.append("pane \(terminalPaneIdentifier)") }
      return parts.joined(separator: " · ")
   }

   var dictionary: [String: Any] {
      var result: [String: Any] = [
         "id": id,
         "channelId": channelId,
         "displayIdentifier": displayIdentifier,
         "sessionHeader": sessionHeader,
         "label": label,
         "processName": processName,
         "parentProcessID": Int(parentProcessID),
         "transport": transport,
         "terminalApplication": terminalApplication,
         "colorName": colorName,
         "colorHex": colorHex,
         "connectedAt": Self.isoFormatter.string(from: connectedAt),
         "state": state.rawValue,
         "permissionState": permissionState.rawValue,
         "receivesSignal": receivesSignal,
      ]
      if let terminalApplicationVersion {
         result["terminalApplicationVersion"] = terminalApplicationVersion
      }
      if let terminalApplicationProcessID {
         result["terminalApplicationProcessID"] = Int(terminalApplicationProcessID)
      }
      if let terminalSessionIdentifier {
         result["terminalSessionIdentifier"] = terminalSessionIdentifier
      }
      if let terminalPaneIdentifier { result["terminalPaneIdentifier"] = terminalPaneIdentifier }
      if let agentTopBarText { result["agentTopBarText"] = agentTopBarText }
      if let clientName { result["clientName"] = clientName }
      if let clientVersion { result["clientVersion"] = clientVersion }
      return result
   }

   private static let isoFormatter: ISO8601DateFormatter = {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter
   }()
}

final class TerminalSessionColorAllocator {
   private var usedHues: [Double] = []
   private var paletteIndex = 0

   func nextColor() -> TerminalSessionColorSpec {
      if paletteIndex < Self.palette.count {
         let color = Self.palette[paletteIndex]
         paletteIndex += 1
         usedHues.append(color.hueDegrees)
         return color
      }

      let hue = farthestUnusedHue()
      usedHues.append(hue)
      return TerminalSessionColorSpec(
         name: "Hue \(Int(hue.rounded()))",
         hex: Self.hexForHSB(hueDegrees: hue, saturation: 0.82, brightness: 0.92),
         hueDegrees: hue)
   }

   // Deliberately high-contrast, non-adjacent hues. Do not reorder into gradients:
   // adjacent entries are what simultaneous terminal sessions receive.
   private static let palette: [TerminalSessionColorSpec] = [
      TerminalSessionColorSpec(name: "Signal Blue", hex: "#0072B2", hueDegrees: 202),
      TerminalSessionColorSpec(name: "Vermilion", hex: "#D55E00", hueDegrees: 26),
      TerminalSessionColorSpec(name: "Bluish Green", hex: "#009E73", hueDegrees: 164),
      TerminalSessionColorSpec(name: "Reddish Purple", hex: "#CC79A7", hueDegrees: 326),
      TerminalSessionColorSpec(name: "Golden Yellow", hex: "#F0E442", hueDegrees: 56),
      TerminalSessionColorSpec(name: "Royal Purple", hex: "#6F42C1", hueDegrees: 262),
      TerminalSessionColorSpec(name: "Lime", hex: "#7CB342", hueDegrees: 92),
      TerminalSessionColorSpec(name: "Emerald", hex: "#22C55E", hueDegrees: 128),
   ]

   private func farthestUnusedHue() -> Double {
      var bestHue = 0.0
      var bestDistance = -1.0
      for candidate in stride(from: 0.0, through: 359.0, by: 1.0) {
         let distance = usedHues.map { Self.circularDistance(candidate, $0) }.min() ?? 180.0
         if distance > bestDistance {
            bestDistance = distance
            bestHue = candidate
         }
      }
      return bestHue
   }

   private static func circularDistance(_ lhs: Double, _ rhs: Double) -> Double {
      let diff = abs(lhs - rhs).truncatingRemainder(dividingBy: 360.0)
      return min(diff, 360.0 - diff)
   }

   private static func hexForHSB(hueDegrees: Double, saturation: Double, brightness: Double)
      -> String
   {
      let hue = hueDegrees / 60.0
      let chroma = brightness * saturation
      let x = chroma * (1.0 - abs(hue.truncatingRemainder(dividingBy: 2.0) - 1.0))
      let m = brightness - chroma
      let rgb: (Double, Double, Double)

      switch hue {
      case 0..<1: rgb = (chroma, x, 0)
      case 1..<2: rgb = (x, chroma, 0)
      case 2..<3: rgb = (0, chroma, x)
      case 3..<4: rgb = (0, x, chroma)
      case 4..<5: rgb = (x, 0, chroma)
      default: rgb = (chroma, 0, x)
      }

      let red = Int(((rgb.0 + m) * 255.0).rounded())
      let green = Int(((rgb.1 + m) * 255.0).rounded())
      let blue = Int(((rgb.2 + m) * 255.0).rounded())
      return String(format: "#%02X%02X%02X", red, green, blue)
   }
}
