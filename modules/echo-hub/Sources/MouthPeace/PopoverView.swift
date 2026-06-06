import Foundation
import SwiftUI

/// Popover UI: header, mic status, PTT/listen toggle, status display,
/// last transcription, hotkey recorder, footer.
struct PopoverView: View {
   @EnvironmentObject var appState: AppState
   @StateObject private var mic = MicrophonePermission()

   var body: some View {
      VStack(alignment: .leading, spacing: 12) {
         header
         Divider()
         micRow
         listenToggle
         statusRow
         transcriptionRow
         Divider()
         machineAPIRow
         terminalSessionsRow
         turnSettingsRow
         hotKeyRow
         footer
      }
      .padding(16)
      .frame(width: 420)
      .onAppear { mic.refresh() }
   }

   /// Short marketing version, e.g. "v0.1.1" — glanceable in the header.
   private var versionShort: String {
      let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
      return "v\(v)"
   }

   /// Full build provenance: version · build stamp · git commit. The build stamp
   /// and commit are injected by build.sh, so every build is uniquely identifiable.
   private var versionFull: String {
      let info = Bundle.main.infoDictionary
      let short = info?["CFBundleShortVersionString"] as? String ?? "?"
      let build = info?["CFBundleVersion"] as? String ?? "?"
      let commit = info?["MouthPeaceGitCommit"] as? String ?? ""
      return commit.isEmpty ? "v\(short) · build \(build)" : "v\(short) · build \(build) · \(commit)"
   }

   private var header: some View {
      let accent = headerAccentColor
      return HStack(spacing: 10) {
         Image(systemName: "waveform.circle.fill")
            .font(.title2)
            .foregroundStyle(accent)
         VStack(alignment: .leading, spacing: 2) {
            Text("Echo")
               .font(.headline)
               .foregroundStyle(accent)
            Text(versionShort)
               .font(.caption2)
               .foregroundStyle(.secondary)
            if let session = primaryTerminalSession {
               Text(session.displayIdentifier)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
            }
         }
         Spacer()
         Circle()
            .fill(statusDotColor)
            .frame(width: 8, height: 8)
      }
      .padding(10)
      .background(
         RoundedRectangle(cornerRadius: 12)
            .fill(accent.opacity(primaryTerminalSession == nil ? 0.08 : 0.14))
      )
      .overlay(
         RoundedRectangle(cornerRadius: 12)
            .stroke(accent.opacity(primaryTerminalSession == nil ? 0.18 : 0.55), lineWidth: 1)
      )
   }

   private var micRow: some View {
      HStack(spacing: 8) {
         Image(systemName: micIconName)
            .foregroundStyle(micIconColor)
         VStack(alignment: .leading, spacing: 2) {
            Text("Microphone")
               .font(.subheadline)
            Text(micStatusText)
               .font(.caption)
               .foregroundStyle(.secondary)
         }
         Spacer()
         micActionButton
      }
   }

   @ViewBuilder
   private var micActionButton: some View {
      switch mic.status {
      case .notDetermined:
         Button("Allow…") {
            Task { await mic.request() }
         }
         .controlSize(.small)
      case .denied, .restricted:
         Button("Settings…") {
            MicrophonePermission.openSystemSettings()
         }
         .controlSize(.small)
      case .authorized:
         Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
      }
   }

   private var listenToggle: some View {
      Button(action: {
         if mic.status == .notDetermined {
            Task { await mic.request() }
            return
         }
         appState.onListeningToggle?(!appState.isListening)
      }) {
         HStack {
            Image(systemName: listenIcon)
            Text(listenLabel)
               .fontWeight(.medium)
         }
         .frame(maxWidth: .infinity)
         .padding(.vertical, 10)
         .background(
            RoundedRectangle(cornerRadius: 8)
               .fill(
                  appState.isListening ? Color.red.opacity(0.15) : Color.accentColor.opacity(0.12))
         )
      }
      .buttonStyle(.plain)
   }

   private var statusRow: some View {
      HStack(spacing: 6) {
         if appState.isListening {
            Image(systemName: "waveform")
               .foregroundStyle(.green)
               .symbolEffect(.variableColor.iterative, isActive: appState.isListening)
         }
         if appState.isSpeaking {
            Image(systemName: "speaker.wave.2.fill")
               .foregroundStyle(.blue)
         }
         Text(appState.statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
         Spacer()
      }
   }

   @ViewBuilder
   private var transcriptionRow: some View {
      if let text = appState.lastTranscription {
         VStack(alignment: .leading, spacing: 4) {
            Text("Last heard:")
               .font(.caption2)
               .foregroundStyle(.secondary)
            Text(text)
               .font(.caption)
               .padding(8)
               .frame(maxWidth: .infinity, alignment: .leading)
               .background(
                  RoundedRectangle(cornerRadius: 6)
                     .fill(Color.secondary.opacity(0.08))
               )
               .lineLimit(3)
         }
      }
   }

   private var hotKeyRow: some View {
      VStack(alignment: .leading, spacing: 6) {
         HStack {
            Text("Shortcut")
               .font(.subheadline)
            Spacer()
            if !appState.lastRegistrationSucceeded {
               Text("Registration failed")
                  .font(.caption2)
                  .foregroundStyle(.red)
            }
         }
         HotKeyRecorder(hotKey: $appState.currentHotKey)
            .frame(height: 28)
         Text("Click the field, then press a key combo with at least one modifier.")
            .font(.caption2)
            .foregroundStyle(.secondary)
      }
   }
   private var machineAPIRow: some View {
      VStack(alignment: .leading, spacing: 4) {
         Text("Machine API")
            .font(.subheadline)
         Text(
            appState.restBaseURL.isEmpty
               ? "Starting authenticated REST API…" : "\(appState.restBaseURL) · Bearer auth"
         )
         .font(.caption2)
         .foregroundStyle(.secondary)
         .textSelection(.enabled)
         .lineLimit(2)
      }
   }

   private var terminalSessionsRow: some View {
      VStack(alignment: .leading, spacing: 10) {
         HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
               .foregroundStyle(headerAccentColor)
            Text("Echo session")
               .font(.subheadline)
               .fontWeight(.semibold)
            Spacer()
            Text("\(connectedTerminalCount)/1")
               .font(.caption.monospacedDigit())
               .foregroundStyle(.secondary)
         }

         if appState.terminalSessions.isEmpty {
            emptyTerminalSessionsCard
         } else {
            ForEach(appState.terminalSessions) { session in
               terminalSessionCard(session)
            }
         }
      }
      .padding(12)
      .background(
         RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.07))
      )
      .overlay(
         RoundedRectangle(cornerRadius: 12)
            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
      )
   }

   private var emptyTerminalSessionsCard: some View {
      VStack(alignment: .leading, spacing: 4) {
         Text("No Echo session approved")
            .font(.caption)
            .fontWeight(.medium)
         Text("Every terminal connection requires human approval. Only one session may exist.")
            .font(.caption2)
            .foregroundStyle(.secondary)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(
         RoundedRectangle(cornerRadius: 10)
            .stroke(Color.secondary.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
      )
   }

   private func terminalSessionCard(_ session: TerminalSession) -> some View {
      let color = terminalColor(session.colorHex)
      let isConnected = session.state == .connected
      return HStack(alignment: .top, spacing: 10) {
         RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 5)
         VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
               Text(session.displayIdentifier)
                  .font(.caption)
                  .fontWeight(.semibold)
                  .foregroundStyle(isConnected ? .primary : .secondary)
                  .lineLimit(2)
               Spacer()
               Text(session.permissionState.rawValue.capitalized)
                  .font(.caption2.monospacedDigit())
                  .padding(.horizontal, 6)
                  .padding(.vertical, 3)
                  .background(Capsule().fill(color.opacity(0.18)))
                  .foregroundStyle(color)
               Button {
                  appState.onTerminalSessionSignalChange?(
                     session.id, !session.receivesSignal)
               } label: {
                  Label(
                     session.receivesSignal ? "SIGNAL ON" : "SIGNAL OFF",
                     systemImage: session.receivesSignal
                        ? "antenna.radiowaves.left.and.right"
                        : "antenna.radiowaves.left.and.right.slash")
               }
               .controlSize(.small)
               .disabled(!isConnected)
               Button(role: .destructive) {
                  appState.onTerminalSessionKill?(session.id)
               } label: {
                  Label("KILL SESSION", systemImage: "xmark.octagon.fill")
               }
               .controlSize(.small)
               .disabled(!isConnected)
            }

            Text("Terminal app: \(session.terminalApplication)")
               .font(.caption2)
               .foregroundStyle(.secondary)

            Text("Agent top bar: \(session.agentTopBarText ?? "Unavailable")")
               .font(.caption2)
               .foregroundStyle(.secondary)
               .textSelection(.enabled)
               .lineLimit(2)

            HStack(spacing: 6) {
               Text(sessionStateText(session.state))
                  .font(.caption2)
                  .foregroundStyle(isConnected ? .secondary : .tertiary)
               Text("•")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
               Text(session.receivesSignal ? "Receives signal" : "Signal muted")
                  .font(.caption2)
                  .foregroundStyle(session.receivesSignal ? color : .secondary)
            }

            Text("Echo session #\(session.id) · Channel \(session.channelId)")
               .font(.caption2.monospacedDigit())
               .foregroundStyle(session.receivesSignal ? color : .secondary)

            Text(session.sessionHeader)
               .font(.caption2.monospaced())
               .foregroundStyle(.secondary)
               .lineLimit(3)
         }
      }
      .padding(10)
      .background(
         RoundedRectangle(cornerRadius: 10)
            .fill(color.opacity(isConnected ? 0.12 : 0.04))
      )
      .overlay(
         RoundedRectangle(cornerRadius: 10)
            .stroke(color.opacity(isConnected ? 0.55 : 0.22), lineWidth: 1)
      )
   }

   private var turnSettingsRow: some View {
      VStack(alignment: .leading, spacing: 10) {
         HStack {
            Text("Voice control panel")
               .font(.subheadline)
            Spacer()
            Text("1–10")
               .font(.caption2)
               .foregroundStyle(.secondary)
         }

         sensitivitySlider(
            title: "Barge-in sensitivity",
            value: bargeInSensitivityBinding,
            valueText: "\(bargeInSensitivityValue)/10",
            help: "Higher interrupts sooner while TTS is talking.")

         sensitivitySlider(
            title: "Turn-close sensitivity",
            value: turnCloseSensitivityBinding,
            valueText: "\(turnCloseSensitivityValue)/10",
            help: "Higher closes your turn sooner after silence.")

         Text(
            "Tuned: silence \(appState.conversationSettings.humanTurnSilenceSeconds, specifier: "%.1f")s · barge \(appState.conversationSettings.bargeInThreshold, specifier: "%.3f") RMS · \(appState.conversationSettings.bargeInRequiredFrames) frames · guard \(appState.conversationSettings.bargeInArmDelaySeconds, specifier: "%.1f")s"
         )
         .font(.caption2)
         .foregroundStyle(.secondary)
         .lineLimit(3)
      }
      .padding(10)
      .background(
         RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.08))
      )
   }

   private func sensitivitySlider(
      title: String,
      value: Binding<Double>,
      valueText: String,
      help: String
   ) -> some View {
      VStack(alignment: .leading, spacing: 4) {
         HStack {
            Text(title).font(.caption)
            Spacer()
            Text(valueText)
               .font(.caption.monospacedDigit())
               .foregroundStyle(.secondary)
         }
         Slider(value: value, in: 1...10, step: 1)
         Text(help)
            .font(.caption2)
            .foregroundStyle(.secondary)
      }
   }

   private var bargeInSensitivityValue: Int {
      let threshold = Double(appState.conversationSettings.bargeInThreshold)
      let raw = 1.0 + ((0.35 - threshold) / (0.35 - 0.06)) * 9.0
      return clampSensitivity(raw)
   }

   private var bargeInSensitivityBinding: Binding<Double> {
      Binding(
         get: { Double(bargeInSensitivityValue) },
         set: { newValue in
            let level = Double(clampSensitivity(newValue))
            var settings = appState.conversationSettings
            settings.bargeInThreshold = Float(0.35 - ((level - 1.0) / 9.0) * (0.35 - 0.06))
            settings.bargeInRequiredFrames = max(2, 8 - Int(level.rounded()))
            appState.onConversationSettingsChange?(settings.sanitized)
         })
   }

   private var turnCloseSensitivityValue: Int {
      let silence = appState.conversationSettings.humanTurnSilenceSeconds
      let raw = 1.0 + ((5.0 - silence) / (5.0 - 0.7)) * 9.0
      return clampSensitivity(raw)
   }

   private var turnCloseSensitivityBinding: Binding<Double> {
      Binding(
         get: { Double(turnCloseSensitivityValue) },
         set: { newValue in
            let level = Double(clampSensitivity(newValue))
            var settings = appState.conversationSettings
            settings.humanTurnSilenceSeconds = 5.0 - ((level - 1.0) / 9.0) * (5.0 - 0.7)
            appState.onConversationSettingsChange?(settings.sanitized)
         })
   }

   private func clampSensitivity(_ value: Double) -> Int {
      max(1, min(10, Int(value.rounded())))
   }

   private var footer: some View {
      HStack {
         Text("Right-click menu bar icon for options.")
            .font(.caption2)
            .foregroundStyle(.secondary)
         Spacer()
         Text(versionFull)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
      }
   }

   private func conversationDoubleBinding(
      get: @escaping (ConversationSettings) -> TimeInterval,
      set: @escaping (inout ConversationSettings, TimeInterval) -> Void
   ) -> Binding<Double> {
      Binding(
         get: { get(appState.conversationSettings) },
         set: { newValue in
            var settings = appState.conversationSettings
            set(&settings, newValue)
            appState.onConversationSettingsChange?(settings.sanitized)
         })
   }

   private func conversationFloatBinding(
      get: @escaping (ConversationSettings) -> Float,
      set: @escaping (inout ConversationSettings, Float) -> Void
   ) -> Binding<Double> {
      Binding(
         get: { Double(get(appState.conversationSettings)) },
         set: { newValue in
            var settings = appState.conversationSettings
            set(&settings, Float(newValue))
            appState.onConversationSettingsChange?(settings.sanitized)
         })
   }

   private func conversationIntBinding(
      get: @escaping (ConversationSettings) -> Int,
      set: @escaping (inout ConversationSettings, Int) -> Void
   ) -> Binding<Int> {
      Binding(
         get: { get(appState.conversationSettings) },
         set: { newValue in
            var settings = appState.conversationSettings
            set(&settings, newValue)
            appState.onConversationSettingsChange?(settings.sanitized)
         })
   }

   // MARK: - Helpers

   private var primaryTerminalSession: TerminalSession? {
      appState.terminalSessions.first { $0.state == .connected }
   }

   private var connectedTerminalCount: Int {
      appState.terminalSessions.reduce(0) { count, session in
         count + (session.state == .connected ? 1 : 0)
      }
   }

   private var headerAccentColor: Color {
      guard let session = primaryTerminalSession else { return .accentColor }
      return terminalColor(session.colorHex)
   }

   private func terminalColor(_ hex: String) -> Color {
      Color.echoTerminalHex(hex)
   }

   private func sessionStateText(_ state: TerminalSessionState) -> String {
      switch state {
      case .connected: return "Connected"
      case .disconnected: return "Disconnected"
      }
   }

   private var statusDotColor: Color {
      if appState.isSpeaking { return .blue }
      if appState.isListening { return .green }
      return .secondary
   }

   private var listenIcon: String {
      appState.isListening ? "stop.fill" : "mic.fill"
   }

   private var listenLabel: String {
      appState.isListening ? "Stop Listening" : "Start Listening"
   }

   private var micIconName: String {
      switch mic.status {
      case .authorized: return "mic.fill"
      case .denied,
         .restricted:
         return "mic.slash.fill"
      case .notDetermined: return "mic"
      }
   }

   private var micIconColor: Color {
      switch mic.status {
      case .authorized: return .green
      case .denied,
         .restricted:
         return .red
      case .notDetermined: return .secondary
      }
   }

   private var micStatusText: String {
      switch mic.status {
      case .notDetermined: return "Permission not yet requested"
      case .denied: return "Access denied — open Settings to grant"
      case .restricted: return "Restricted by policy"
      case .authorized: return "Access granted"
      }
   }
}

extension Color {
   fileprivate static func echoTerminalHex(_ hex: String) -> Color {
      let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
      guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else {
         return .accentColor
      }
      let red = Double((value >> 16) & 0xFF) / 255.0
      let green = Double((value >> 8) & 0xFF) / 255.0
      let blue = Double(value & 0xFF) / 255.0
      return Color(red: red, green: green, blue: blue)
   }
}
