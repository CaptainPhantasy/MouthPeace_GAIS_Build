import AVFoundation
import Foundation

/// Captures microphone audio via AVAudioEngine with a simple energy-based VAD gate.
/// Buffers audio while voice is detected, delivers complete utterances as float arrays.
final class AudioService {
   enum State {
      case idle
      case listening
      case processing
   }

   /// Called on audio thread with raw PCM buffers for streaming STT.
   var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

   /// Called on main thread with PCM float samples of a complete utterance.
   var onUtterance: (([Float]) -> Void)?

   /// Called on main thread when state changes.
   var onStateChange: ((State) -> Void)?

   /// Called on main thread when user speech is detected while TTS is playing.
   var onInterruption: (() -> Void)?

   private let engine = AVAudioEngine()
   var hardwareFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }
   private var audioBuffer: [Float] = []
   private let tapBufferDuration: TimeInterval = 0.05  // 50ms chunks for lower capture latency
   private var currentSampleRate: Double = 16000
   private var state: State = .idle {
      didSet {
         let s = state
         DispatchQueue.main.async { self.onStateChange?(s) }
      }
   }

   // VAD parameters
   private var settings = ConversationSettings.defaults
   private let settingsLock = NSLock()
   private let vadThreshold: Float = 0.01  // RMS energy threshold
   private var lastVoiceTime: Date?
   private var silenceTimer: Timer?
   private let vadLock = NSLock()

   // Feedback prevention: mute STT while TTS is playing, but keep a high-threshold
   // barge-in detector alive so the user can interrupt speech output.
   private var isMutedStorage = false
   private let muteLock = NSLock()
   private var mutedStartedAt = Date(timeIntervalSince1970: 0)
   private var interruptionFrames = 0
   private var interruptionTriggered = false

   func mute() {
      muteLock.lock()
      isMutedStorage = true
      mutedStartedAt = Date()
      interruptionFrames = 0
      interruptionTriggered = false
      muteLock.unlock()

      vadLock.lock()
      audioBuffer.removeAll()
      lastVoiceTime = nil
      vadLock.unlock()
      DispatchQueue.main.async { [weak self] in
         self?.silenceTimer?.invalidate()
         self?.silenceTimer = nil
      }
   }

   func unmute() {
      muteLock.lock()
      isMutedStorage = false
      interruptionFrames = 0
      interruptionTriggered = false
      muteLock.unlock()
   }

   private var isCaptureMuted: Bool {
      muteLock.lock()
      let muted = isMutedStorage
      muteLock.unlock()
      return muted
   }
   func updateSettings(_ newSettings: ConversationSettings) {
      settingsLock.lock()
      settings = newSettings.sanitized
      let closeDelay = settings.humanTurnSilenceSeconds
      settingsLock.unlock()
      DispatchQueue.main.async { [weak self] in
         guard let self, self.state == .listening else { return }
         self.silenceTimer?.invalidate()
         self.silenceTimer = Timer.scheduledTimer(withTimeInterval: closeDelay, repeats: false) {
            [weak self] _ in
            self?.onSilenceTimeout()
         }
      }
   }

   func currentSettings() -> ConversationSettings {
      settingsLock.lock()
      let value = settings
      settingsLock.unlock()
      return value
   }

   // MARK: - Start / Stop

   /// True once we have installed an input tap that must be removed before re-tapping.
   /// Tracked independently of `state` so teardown never depends on the state machine
   /// agreeing with reality — a mismatch is exactly what made `installTap` throw.
   private var tapInstalled = false
   private var configChangeObserver: NSObjectProtocol?

   func startListening() throws {
      guard state == .idle else { return }
      try rebuildAudioGraph()
      audioBuffer.removeAll()
      lastVoiceTime = nil
      state = .listening
      observeConfigurationChanges()
   }

   /// Idempotent (re)build of the capture graph. Safe to call when a tap is already
   /// installed or after an audio-route change. This is the single chokepoint for the
   /// two failure modes that lived in the tap/format/engine lifecycle:
   ///   1. CRASH: `installTap` raises an *uncatchable* Obj-C NSException ("only one tap
   ///      per bus" or "required condition is false: format.sampleRate") — so we PREVENT
   ///      it by always removing any prior tap and validating the format before tapping.
   ///   2. DEAFNESS: after a route change the old tap is bound to the gone device — we
   ///      re-read the *fresh* hardware format and re-tap.
   ///
   /// NOTE: OS voice-processing (`setVoiceProcessingEnabled`) is deliberately NOT used.
   /// On macOS it switches the input to a duplex VoiceProcessingIO unit (observed: 4ch
   /// @32kHz) that yields no capture audio in this output-less, capture-only engine — it
   /// silently broke the mic. It also only cancels engine-rendered output, while TTS uses
   /// AVSpeechSynthesizer (a separate path), so it wouldn't have stopped feedback anyway.
   /// Feedback is handled by muting capture during TTS; headphones remain the clean fix.
   private func rebuildAudioGraph() throws {
      let inputNode = engine.inputNode

      // Always tear down first — independent of `state`. Removing an absent tap is a no-op,
      // but reinstalling over a present one aborts the process. (root cause of the SIGABRT)
      if tapInstalled {
         inputNode.removeTap(onBus: 0)
         tapInstalled = false
      }
      if engine.isRunning {
         engine.stop()
      }

      // Read the format AFTER any device/route change.
      let hardwareFormat = inputNode.outputFormat(forBus: 0)
      guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
         // Invalid format (mid route-flip): bail cleanly instead of letting installTap abort.
         throw AudioError.noMicrophone
      }

      let bufferSize = AVAudioFrameCount(hardwareFormat.sampleRate * tapBufferDuration)
      inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) {
         [weak self] buffer, _ in
         guard let self else { return }
         guard let channelData = buffer.floatChannelData else { return }
         let samples = UnsafeBufferPointer(
            start: channelData[0],
            count: Int(buffer.frameLength))
         if self.isCaptureMuted {
            self.processInterruptionSamples(samples)
            return
         }
         self.onAudioBuffer?(buffer)
         self.processAudioSamples(samples)
      }
      tapInstalled = true

      engine.prepare()
      try engine.start()
      currentSampleRate = hardwareFormat.sampleRate
      let activeSettings = currentSettings()
      NSLog(
         "MouthPeace Audio: listening at \(hardwareFormat.sampleRate)Hz \(hardwareFormat.channelCount)ch, chunk=\(Int(tapBufferDuration * 1000))ms, silence=\(Int(activeSettings.humanTurnSilenceSeconds * 1000))ms"
      )
   }

   /// Rebind the capture graph when the audio route changes (e.g. earbuds connect/disconnect).
   /// macOS uses `AVAudioEngineConfigurationChange` — `AVAudioSession` is iOS-only.
   private func observeConfigurationChanges() {
      guard configChangeObserver == nil else { return }
      configChangeObserver = NotificationCenter.default.addObserver(
         forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
      ) { [weak self] _ in
         guard let self, self.state == .listening else { return }
         NSLog("MouthPeace Audio: configuration changed — rebuilding capture graph")
         do {
            try self.rebuildAudioGraph()
         } catch {
            NSLog("MouthPeace Audio: rebuild after route change failed: \(error.localizedDescription)")
            self.state = .idle
         }
      }
   }

   func stopListening() {
      guard state == .listening || state == .processing else { return }
      if tapInstalled {
         engine.inputNode.removeTap(onBus: 0)
         tapInstalled = false
      }
      engine.stop()
      silenceTimer?.invalidate()
      silenceTimer = nil

      // If there's buffered audio, deliver it
      if !audioBuffer.isEmpty {
         deliverUtterance()
      }
      state = .idle
      NSLog("MouthPeace Audio: listening stopped")
   }

   private func processAudioSamples(_ samples: UnsafeBufferPointer<Float>) {
      let rms = rmsEnergy(samples)

      vadLock.lock()
      if rms >= vadThreshold {
         lastVoiceTime = Date()
         audioBuffer.append(contentsOf: samples)
         vadLock.unlock()

         DispatchQueue.main.async { [weak self] in
            self?.resetSilenceTimer()
         }
      } else {
         if lastVoiceTime != nil {
            audioBuffer.append(contentsOf: samples)
         }
         vadLock.unlock()
      }
   }

   private func processInterruptionSamples(_ samples: UnsafeBufferPointer<Float>) {
      let rms = rmsEnergy(samples)
      let now = Date()

      let activeSettings = currentSettings()
      muteLock.lock()
      let armed = now.timeIntervalSince(mutedStartedAt) >= activeSettings.bargeInArmDelaySeconds
      if !isMutedStorage || interruptionTriggered || !armed {
         muteLock.unlock()
         return
      }
      if rms >= activeSettings.bargeInThreshold {
         interruptionFrames += 1
      } else {
         interruptionFrames = 0
      }
      let shouldInterrupt = interruptionFrames >= activeSettings.bargeInRequiredFrames
      if shouldInterrupt {
         interruptionTriggered = true
      }
      muteLock.unlock()

      guard shouldInterrupt else { return }
      NSLog(
         "MouthPeace Audio: interruption detected while muted (rms=\(rms), frames=\(interruptionFrames))"
      )
      DispatchQueue.main.async { [weak self] in
         self?.onInterruption?()
      }
   }

   private func rmsEnergy(_ samples: UnsafeBufferPointer<Float>) -> Float {
      var sum: Float = 0
      for sample in samples {
         sum += sample * sample
      }
      return sqrt(sum / max(Float(samples.count), 1))
   }

   private func resetSilenceTimer() {
      silenceTimer?.invalidate()
      let closeDelay = currentSettings().humanTurnSilenceSeconds
      silenceTimer = Timer.scheduledTimer(withTimeInterval: closeDelay, repeats: false) {
         [weak self] _ in
         self?.onSilenceTimeout()
      }
   }

   private func onSilenceTimeout() {
      vadLock.lock()
      let hasAudio = !audioBuffer.isEmpty
      vadLock.unlock()

      if hasAudio {
         deliverUtterance()
      }
   }

   private func deliverUtterance() {
      vadLock.lock()
      let samples = audioBuffer
      audioBuffer.removeAll()
      lastVoiceTime = nil
      vadLock.unlock()

      guard !samples.isEmpty else { return }

      let shouldKeepListening = engine.isRunning
      let durationMs = Int(Double(samples.count) / currentSampleRate * 1000)
      NSLog("MouthPeace Audio: utterance captured, \(samples.count) samples (\(durationMs)ms)")

      state = .processing
      DispatchQueue.main.async { [weak self] in
         guard let self else { return }
         self.onUtterance?(samples)
         if shouldKeepListening && self.engine.isRunning {
            self.state = .listening
         } else {
            self.state = .idle
         }
      }
   }

   func resumeListening() {
      if engine.isRunning {
         state = .listening
      }
   }

   enum AudioError: LocalizedError {
      case noMicrophone
      case formatError

      var errorDescription: String? {
         switch self {
         case .noMicrophone: return "No microphone input available"
         case .formatError: return "Failed to create audio format"
         }
      }
   }
}
