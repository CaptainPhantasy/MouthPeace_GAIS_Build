import AVFoundation
import Foundation

/// Text-to-speech via AVSpeechSynthesizer.
/// Provides a mute callback so AudioService can suppress mic during playback
/// to prevent feedback loops.
final class TTSService: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {

   private let synthesizer = AVSpeechSynthesizer()
   private let selectedVoice: AVSpeechSynthesisVoice?

   /// Called when speech starts — mute the mic.
   var onSpeakingStarted: (() -> Void)?
   /// Called when speech ends — unmute the mic.
   var onSpeakingEnded: (() -> Void)?

   private var pendingUtterances: [ObjectIdentifier] = []
   private var speechCompletions: [ObjectIdentifier: () -> Void] = [:]

   override init() {
      self.selectedVoice = Self.resolveVoice()
      super.init()
      synthesizer.delegate = self
      if let v = selectedVoice {
         NSLog(
            "MouthPeace TTS: using voice '\(v.name)' (\(v.identifier), quality=\(v.quality.rawValue))"
         )
      } else {
         NSLog("MouthPeace TTS: falling back to default en-US voice")
      }
   }

   /// Resolves the preferred voice:
   ///   1. $MOUTHPEACE_TTS_VOICE (matches voice.name or voice.identifier; case-insensitive substring)
   ///   2. Douglas's ordered Personal Voice 1 when installed and authorized
   ///   3. Any English Personal Voice for the current user if authorized
   ///   4. Highest-quality en-US voice (premium > enhanced > default)
   private static func resolveVoice() -> AVSpeechSynthesisVoice? {
      let voices = AVSpeechSynthesisVoice.speechVoices()

      if let pref = ProcessInfo.processInfo.environment["MOUTHPEACE_TTS_VOICE"],
         !pref.isEmpty
      {
         let needle = pref.lowercased()
         if let match = voices.first(where: {
            $0.name.lowercased().contains(needle) || $0.identifier.lowercased().contains(needle)
         }) {
            return match
         }
         NSLog(
            "MouthPeace TTS: no voice matches MOUTHPEACE_TTS_VOICE=\(pref); falling through"
         )
      }

      if #available(macOS 14.0, *),
         AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized
      {
         let orderedVoiceIdentifier =
            "com.apple.speech.personalvoice.09CAA5D7-0267-4167-8A65-5E1A8935AE0E"
         if let ordered = voices.first(where: { $0.identifier == orderedVoiceIdentifier }) {
            return ordered
         }
         if let personal = voices.first(where: {
            $0.voiceTraits.contains(.isPersonalVoice) && $0.language.hasPrefix("en")
         }) {
            return personal
         }
      }

      let enUS = voices.filter { $0.language == "en-US" }
      let ranked = enUS.sorted { lhs, rhs in
         lhs.quality.rawValue > rhs.quality.rawValue
      }
      return ranked.first ?? AVSpeechSynthesisVoice(language: "en-US")
   }

   /// Queue text for speech. Calls completion on main thread when this utterance finishes or is cancelled.
   func speak(_ text: String, completion: (() -> Void)? = nil) {
      let speechText = SpeechPronunciation.prepareForSpeech(text)
      guard !speechText.isEmpty else {
         completion?()
         return
      }

      let utterance = AVSpeechUtterance(string: speechText)
      utterance.voice = selectedVoice ?? AVSpeechSynthesisVoice(language: "en-US")
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate
      utterance.pitchMultiplier = 1.0
      utterance.volume = 1.0

      let id = ObjectIdentifier(utterance)
      pendingUtterances.append(id)
      if let completion {
         speechCompletions[id] = completion
      }

      NSLog("MouthPeace TTS: queued speech '\(speechText.prefix(80))...'")
      synthesizer.speak(utterance)
   }

   func stop() {
      guard synthesizer.isSpeaking || !pendingUtterances.isEmpty else { return }
      synthesizer.stopSpeaking(at: .immediate)
      completeAllPendingSpeech()
   }

   var isSpeaking: Bool { synthesizer.isSpeaking }

   // MARK: - AVSpeechSynthesizerDelegate

   func speechSynthesizer(
      _ synthesizer: AVSpeechSynthesizer,
      didStart utterance: AVSpeechUtterance
   ) {
      DispatchQueue.main.async { self.onSpeakingStarted?() }
   }

   func speechSynthesizer(
      _ synthesizer: AVSpeechSynthesizer,
      didFinish utterance: AVSpeechUtterance
   ) {
      DispatchQueue.main.async {
         self.completeSpeech(for: utterance)
      }
   }

   func speechSynthesizer(
      _ synthesizer: AVSpeechSynthesizer,
      didCancel utterance: AVSpeechUtterance
   ) {
      DispatchQueue.main.async {
         self.completeSpeech(for: utterance)
      }
   }

   private func completeSpeech(for utterance: AVSpeechUtterance) {
      let id = ObjectIdentifier(utterance)
      let completion = speechCompletions.removeValue(forKey: id)
      pendingUtterances.removeAll { $0 == id }
      if pendingUtterances.isEmpty {
         onSpeakingEnded?()
      }
      completion?()
   }

   private func completeAllPendingSpeech() {
      let completions = pendingUtterances.compactMap { speechCompletions[$0] }
      pendingUtterances.removeAll()
      speechCompletions.removeAll()
      onSpeakingEnded?()
      completions.forEach { $0() }
   }
}
