import Foundation

final class DialogueOrchestrator {
   struct Agent: Equatable {
      let name: String
      let role: String

      var dictionary: [String: Any] {
         ["name": name, "role": role]
      }
   }
   struct PlannedTurn: Equatable {
      let speaker: String
      let text: String

      var dictionary: [String: Any] {
         ["speaker": speaker, "text": text]
      }
   }

   struct StartRequest {
      let dialogueCount: Int
      let dialogueDurationSeconds: TimeInterval
      let turnIntervalSeconds: TimeInterval
      let maxTurnsPerDialogue: Int?
      let topic: String
      let agentA: Agent
      let agentB: Agent
      let plannedTurns: [PlannedTurn]

      static let defaultDialogueCount = 10
      static let defaultDialogueDurationSeconds: TimeInterval = 180.0
      static let defaultTurnIntervalSeconds: TimeInterval = 2.5

      init(params: [String: Any]) throws {
         dialogueCount = try Self.intValue(
            params["dialogueCount"], name: "dialogueCount", fallback: Self.defaultDialogueCount,
            range: 1...50)
         dialogueDurationSeconds = try Self.doubleValue(
            params["dialogueDurationSeconds"], name: "dialogueDurationSeconds",
            fallback: Self.defaultDialogueDurationSeconds, min: 0.05, max: 3600)
         turnIntervalSeconds = try Self.doubleValue(
            params["turnIntervalSeconds"], name: "turnIntervalSeconds",
            fallback: Self.defaultTurnIntervalSeconds, min: Self.defaultTurnIntervalSeconds,
            max: 600)
         if let maxTurns = params["maxTurnsPerDialogue"] {
            maxTurnsPerDialogue = try Self.intValue(
               maxTurns, name: "maxTurnsPerDialogue", fallback: 0, range: 1...10_000)
         } else {
            maxTurnsPerDialogue = nil
         }
         topic =
            (params["topic"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "MouthPeace quality hardening"
         agentA = try Self.agent(params["agentA"], fallbackName: "Subagent A")
         agentB = try Self.agent(params["agentB"], fallbackName: "Subagent B")
         plannedTurns = try Self.plannedTurns(params["turns"])
      }

      var dictionary: [String: Any] {
         var result: [String: Any] = [
            "dialogueCount": dialogueCount,
            "dialogueDurationSeconds": dialogueDurationSeconds,
            "turnIntervalSeconds": turnIntervalSeconds,
            "topic": topic,
            "agentA": agentA.dictionary,
            "agentB": agentB.dictionary,
            "turns": plannedTurns.map { $0.dictionary },
         ]
         if let maxTurnsPerDialogue {
            result["maxTurnsPerDialogue"] = maxTurnsPerDialogue
         }
         return result
      }

      private static func agent(_ value: Any?, fallbackName: String) throws -> Agent {
         guard let dict = value as? [String: Any] else {
            return Agent(name: fallbackName, role: "Review MouthPeace behavior")
         }
         let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
         let role = (dict["role"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
         return Agent(
            name: name?.isEmpty == false ? name! : fallbackName,
            role: role?.isEmpty == false ? role! : "Review MouthPeace behavior"
         )
      }

      private static func plannedTurns(_ value: Any?) throws -> [PlannedTurn] {
         guard let rawTurns = value as? [[String: Any]], !rawTurns.isEmpty else {
            throw ToolError.invalidParams(
               "Generated LLM 'turns' are required; MouthPeace will not synthesize placeholder dialogue"
            )
         }
         return try rawTurns.enumerated().map { index, rawTurn in
            guard let speaker = rawTurn["speaker"] as? String,
               !speaker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
               throw ToolError.invalidParams("turns[\(index)].speaker must be a non-empty string")
            }
            guard let text = rawTurn["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
               throw ToolError.invalidParams("turns[\(index)].text must be a non-empty string")
            }
            return PlannedTurn(
               speaker: speaker.trimmingCharacters(in: .whitespacesAndNewlines),
               text: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
         }
      }

      private static func intValue(
         _ value: Any?, name: String, fallback: Int, range: ClosedRange<Int>
      ) throws -> Int {
         guard let value else { return fallback }
         guard let int = value as? Int else {
            throw ToolError.invalidParams("'\(name)' must be an integer")
         }
         guard range.contains(int) else {
            throw ToolError.invalidParams(
               "'\(name)' must be between \(range.lowerBound) and \(range.upperBound)")
         }
         return int
      }

      private static func doubleValue(
         _ value: Any?, name: String, fallback: Double, min: Double, max: Double
      ) throws -> Double {
         guard let value else { return fallback }
         let double: Double
         if let d = value as? Double {
            double = d
         } else if let i = value as? Int {
            double = Double(i)
         } else {
            throw ToolError.invalidParams("'\(name)' must be a number")
         }
         guard double >= min && double <= max else {
            throw ToolError.invalidParams("'\(name)' must be between \(min) and \(max)")
         }
         return double
      }
   }

   struct Event {
      let startedAt: Date
      let endedAt: Date
      let dialogueIndex: Int
      let turnIndex: Int
      let speaker: String
      let text: String
      let error: String?

      var dictionary: [String: Any] {
         var result: [String: Any] = [
            "timestamp": Self.isoFormatter.string(from: endedAt),
            "startedAt": Self.isoFormatter.string(from: startedAt),
            "endedAt": Self.isoFormatter.string(from: endedAt),
            "dialogueIndex": dialogueIndex,
            "turnIndex": turnIndex,
            "speaker": speaker,
            "text": text,
         ]
         if let error {
            result["error"] = error
         }
         return result
      }

      private static let isoFormatter: ISO8601DateFormatter = {
         let formatter = ISO8601DateFormatter()
         formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
         return formatter
      }()
   }

   struct Snapshot {
      let sessionId: String
      let isRunning: Bool
      let totalDialogues: Int
      let dialogueDurationSeconds: TimeInterval
      let turnIntervalSeconds: TimeInterval
      let currentDialogueIndex: Int
      let turnsCompleted: Int
      let activeSpeaker: String
      let startedAt: Date?
      let updatedAt: Date?
      let errors: [String]
      let recentEvents: [Event]

      var dictionary: [String: Any] {
         var result: [String: Any] = [
            "sessionId": sessionId,
            "isRunning": isRunning,
            "totalDialogues": totalDialogues,
            "dialogueDurationSeconds": dialogueDurationSeconds,
            "turnIntervalSeconds": turnIntervalSeconds,
            "currentDialogueIndex": currentDialogueIndex,
            "turnsCompleted": turnsCompleted,
            "activeSpeaker": activeSpeaker,
            "errors": errors,
            "recentEvents": recentEvents.map { $0.dictionary },
         ]
         if let startedAt {
            result["startedAt"] = Self.isoFormatter.string(from: startedAt)
         }
         if let updatedAt {
            result["updatedAt"] = Self.isoFormatter.string(from: updatedAt)
         }
         return result
      }

      private static let isoFormatter: ISO8601DateFormatter = {
         let formatter = ISO8601DateFormatter()
         formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
         return formatter
      }()
   }

   typealias Speak = (_ text: String, _ completion: @escaping () -> Void) -> Void

   private let lock = NSLock()
   private let worker = DispatchQueue(label: "MouthPeace.DialogueOrchestrator", qos: .utility)
   private var cancellation = UUID()
   private var sessionId = "none"
   private var isRunning = false
   private var totalDialogues = StartRequest.defaultDialogueCount
   private var dialogueDurationSeconds = StartRequest.defaultDialogueDurationSeconds
   private var turnIntervalSeconds = StartRequest.defaultTurnIntervalSeconds
   private var currentDialogueIndex = 0
   private var turnsCompleted = 0
   private var activeSpeaker = ""
   private var startedAt: Date?
   private var updatedAt: Date?
   private var errors: [String] = []
   private var recentEvents: [Event] = []
   private var transcriptEvents: [Event] = []

   func start(request: StartRequest, speak: @escaping Speak) throws -> Snapshot {
      lock.lock()
      defer { lock.unlock() }
      guard !isRunning else {
         throw ToolError.invalidParams("Dialogue orchestrator is already running")
      }

      let token = UUID()
      cancellation = token
      sessionId = token.uuidString
      isRunning = true
      let turnsPerDialogue = max(request.maxTurnsPerDialogue ?? request.plannedTurns.count, 1)
      totalDialogues = max(
         1, Int(ceil(Double(request.plannedTurns.count) / Double(turnsPerDialogue))))
      dialogueDurationSeconds = request.dialogueDurationSeconds
      turnIntervalSeconds = request.turnIntervalSeconds
      currentDialogueIndex = 0
      turnsCompleted = 0
      activeSpeaker = ""
      startedAt = Date()
      updatedAt = startedAt
      errors.removeAll(keepingCapacity: true)
      recentEvents.removeAll(keepingCapacity: true)
      transcriptEvents.removeAll(keepingCapacity: true)

      worker.async { [weak self] in
         self?.run(request: request, token: token, speak: speak)
      }
      return snapshotLocked()
   }

   func stop() -> Snapshot {
      lock.lock()
      cancellation = UUID()
      isRunning = false
      activeSpeaker = ""
      updatedAt = Date()
      let snapshot = snapshotLocked()
      lock.unlock()
      return snapshot
   }

   func recordExternalInterruption(reason: String) {
      lock.lock()
      guard isRunning else {
         lock.unlock()
         return
      }
      appendErrorLocked("speech interrupted: \(reason)")
      updatedAt = Date()
      lock.unlock()
   }

   func snapshot() -> Snapshot {
      lock.lock()
      let snapshot = snapshotLocked()
      lock.unlock()
      return snapshot
   }

   func markdownTranscript() -> [String: Any] {
      lock.lock()
      let id = sessionId
      let events = transcriptEvents
      let start = startedAt
      let update = updatedAt
      let capturedErrors = errors
      lock.unlock()

      var lines: [String] = []
      lines.reserveCapacity(12 + events.count * 4 + capturedErrors.count)
      lines.append("# MouthPeace Dialogue Transcript")
      lines.append("")
      lines.append("- Session: `\(id)`")
      if let start {
         lines.append("- Started: \(Self.isoFormatter.string(from: start))")
      }
      if let update {
         lines.append("- Updated: \(Self.isoFormatter.string(from: update))")
      }
      lines.append("- Turns: \(events.count)")
      lines.append("")
      lines.append("## Turns")
      lines.append("")
      for event in events {
         lines.append(
            "### Dialogue \(event.dialogueIndex), Turn \(event.turnIndex) — \(event.speaker)")
         lines.append("")
         lines.append("- Started: \(Self.isoFormatter.string(from: event.startedAt))")
         lines.append("- Ended: \(Self.isoFormatter.string(from: event.endedAt))")
         if let error = event.error {
            lines.append("- Error: \(error)")
         }
         lines.append("")
         lines.append(event.text)
         lines.append("")
      }
      if !capturedErrors.isEmpty {
         lines.append("## Errors")
         lines.append("")
         for error in capturedErrors {
            lines.append("- \(error)")
         }
         lines.append("")
      }
      return [
         "filename": "mouthpeace-dialogue-\(id).md",
         "turns": events.count,
         "markdown": lines.joined(separator: "\n"),
      ]
   }

   private func run(request: StartRequest, token: UUID, speak: @escaping Speak) {
      for (offset, plannedTurn) in request.plannedTurns.enumerated() {
         guard !isCancelled(token) else { return }
         let turnIndex = offset + 1
         let turnsPerDialogue = max(request.maxTurnsPerDialogue ?? request.plannedTurns.count, 1)
         let dialogueIndex = max(1, Int(ceil(Double(turnIndex) / Double(turnsPerDialogue))))
         markDialogue(dialogueIndex)
         speakSynchronously(
            plannedTurn.text, speaker: plannedTurn.speaker, dialogue: dialogueIndex,
            turn: turnIndex,
            token: token, speak: speak)
         guard !isCancelled(token) else { return }
         if turnIndex < request.plannedTurns.count && request.turnIntervalSeconds > 0 {
            Thread.sleep(forTimeInterval: request.turnIntervalSeconds)
         }
      }
      lock.lock()
      if cancellation == token {
         isRunning = false
         activeSpeaker = ""
         updatedAt = Date()
      }
      lock.unlock()
   }

   private func speakSynchronously(
      _ text: String,
      speaker: String,
      dialogue: Int,
      turn: Int,
      token: UUID,
      speak: @escaping Speak
   ) {
      let semaphore = DispatchSemaphore(value: 0)
      let startTime = Date()
      lock.lock()
      activeSpeaker = speaker
      updatedAt = startTime
      lock.unlock()

      speak("\(speaker): \(text)") {
         semaphore.signal()
      }
      semaphore.wait()
      let endTime = Date()

      lock.lock()
      if cancellation == token {
         turnsCompleted += 1
         activeSpeaker = ""
         updatedAt = endTime
         appendEventLocked(
            Event(
               startedAt: startTime, endedAt: endTime, dialogueIndex: dialogue, turnIndex: turn,
               speaker: speaker, text: text, error: nil))
      }
      lock.unlock()
   }

   private func markDialogue(_ dialogue: Int) {
      lock.lock()
      currentDialogueIndex = dialogue
      updatedAt = Date()
      lock.unlock()
   }

   private func isCancelled(_ token: UUID) -> Bool {
      lock.lock()
      let cancelled = cancellation != token
      lock.unlock()
      return cancelled
   }

   private func appendErrorLocked(_ error: String) {
      errors.append(error)
      if errors.count > 100 {
         errors.removeFirst(errors.count - 100)
      }
   }

   private func appendEventLocked(_ event: Event) {
      recentEvents.append(event)
      transcriptEvents.append(event)
      if recentEvents.count > 50 {
         recentEvents.removeFirst(recentEvents.count - 50)
      }
      if transcriptEvents.count > 2_000 {
         transcriptEvents.removeFirst(transcriptEvents.count - 2_000)
      }
   }

   private func snapshotLocked() -> Snapshot {
      Snapshot(
         sessionId: sessionId,
         isRunning: isRunning,
         totalDialogues: totalDialogues,
         dialogueDurationSeconds: dialogueDurationSeconds,
         turnIntervalSeconds: turnIntervalSeconds,
         currentDialogueIndex: currentDialogueIndex,
         turnsCompleted: turnsCompleted,
         activeSpeaker: activeSpeaker,
         startedAt: startedAt,
         updatedAt: updatedAt,
         errors: errors,
         recentEvents: recentEvents
      )
   }

   private static let isoFormatter: ISO8601DateFormatter = {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter
   }()
}
