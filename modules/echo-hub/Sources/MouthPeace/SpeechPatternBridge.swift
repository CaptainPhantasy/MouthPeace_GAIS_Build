import Foundation

/// Best-effort bridge to the MouthPeace-local MOUTH2 speech-pattern engine.
///
/// The app always records final transcripts to JSONL. When the copied Python
/// pattern engine is available, it also ingests transcripts asynchronously into
/// a SQLite n-gram/pattern library. This keeps prediction learning off the
/// latency-critical audio/STT/TTS path.
final class SpeechPatternBridge {
   private let queue = DispatchQueue(label: "MouthPeace.SpeechPatternBridge", qos: .utility)
   private let fileManager = FileManager.default
   private let supportDirectory: URL
   private let eventsURL: URL
   private let databaseURL: URL
   private let engineURL: URL?

   init() {
      let base =
         fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
         .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
      supportDirectory = base.appendingPathComponent("MouthPeace", isDirectory: true)
      eventsURL = supportDirectory.appendingPathComponent("speech-events.jsonl")
      databaseURL = supportDirectory.appendingPathComponent("speech_patterns.sqlite3")
      engineURL = Self.resolveEngineURL(fileManager: fileManager)
   }

   func recordFinalTranscript(_ text: String, source: String = "mouthpeace") {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      let event = TranscriptEvent(text: trimmed, source: source, createdAt: Self.isoTimestamp())
      queue.async { [eventsURL, databaseURL, engineURL, supportDirectory, fileManager] in
         do {
            try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try Self.appendJSONLine(event, to: eventsURL)
            if let engineURL {
               Self.ingestWithPatternEngine(
                  engineURL: engineURL, databaseURL: databaseURL, text: trimmed, source: source)
            }
         } catch {
            NSLog(
               "MouthPeace SpeechPatternBridge: record failed: \(error.localizedDescription)")
         }
      }
   }

   private static func appendJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      var data = try encoder.encode(value)
      data.append(0x0A)
      if FileManager.default.fileExists(atPath: url.path) {
         let handle = try FileHandle(forWritingTo: url)
         defer { try? handle.close() }
         try handle.seekToEnd()
         try handle.write(contentsOf: data)
      } else {
         try data.write(to: url, options: [.atomic])
      }
   }

   private static func ingestWithPatternEngine(
      engineURL: URL, databaseURL: URL, text: String, source: String
   ) {
      let timeout: DispatchTimeInterval = .seconds(10)
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
      process.arguments = [
         engineURL.path,
         "--db", databaseURL.path,
         "ingest",
         "--text", text,
         "--source", source,
      ]
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe
      do {
         try process.run()
         let finished = waitForProcess(process, timeout: timeout)
         if !finished {
            process.terminate()
            _ = waitForProcess(process, timeout: .seconds(2))
            NSLog("MouthPeace SpeechPatternBridge: engine timed out after 10s")
            return
         }
         if process.terminationStatus != 0 {
            let output =
               String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            NSLog(
               "MouthPeace SpeechPatternBridge: engine exited \(process.terminationStatus): \(output)"
            )
         }
      } catch {
         NSLog(
            "MouthPeace SpeechPatternBridge: engine launch failed: \(error.localizedDescription)"
         )
      }
   }
   private static func waitForProcess(_ process: Process, timeout: DispatchTimeInterval) -> Bool {
      let group = DispatchGroup()
      group.enter()
      DispatchQueue.global(qos: .utility).async {
         process.waitUntilExit()
         group.leave()
      }
      return group.wait(timeout: .now() + timeout) == .success
   }

   private static func resolveEngineURL(fileManager: FileManager) -> URL? {
      let env = ProcessInfo.processInfo.environment["MOUTHPEACE_PATTERN_ENGINE"]
      if let env, !env.isEmpty {
         let url = URL(fileURLWithPath: env)
         if fileManager.fileExists(atPath: url.path) { return url }
      }

      let cwdURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
         .appendingPathComponent("Tools/mouth2_speech/pattern_engine.py")
      if fileManager.fileExists(atPath: cwdURL.path) { return cwdURL }

      if let resourcePath = Bundle.main.resourcePath {
         let bundledURL = URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("Tools/mouth2_speech/pattern_engine.py")
         if fileManager.fileExists(atPath: bundledURL.path) { return bundledURL }
      }

      NSLog("MouthPeace SpeechPatternBridge: pattern engine not found; recording JSONL only")
      return nil
   }

   private static func isoTimestamp() -> String {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter.string(from: Date())
   }

   private struct TranscriptEvent: Encodable {
      let text: String
      let source: String
      let createdAt: String
   }
}
