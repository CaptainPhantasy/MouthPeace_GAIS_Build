import AVFoundation
import Foundation
import Speech

/// Streaming speech recognition using SFSpeechRecognizer.
/// Audio is fed directly from AVAudioEngine tap buffers.
/// On-device only. Delivers final transcription when stopped.
final class SpeechService {
   private let recognizer: SFSpeechRecognizer?
   private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
   private var recognitionTask: SFSpeechRecognitionTask?
   private var latestTranscription: String?
   private var isFinishing = false
   private var finishCompletion: (() -> Void)?
   private var finishWorkItem: DispatchWorkItem?
   private let finalizationFallbackDelay: TimeInterval = 0.25

   /// Called on main thread with final transcription when recognition ends.
   var onTranscription: ((String) -> Void)?

   /// Called on main thread with partial results as user speaks.
   var onPartialResult: ((String) -> Void)?

   private(set) var isAvailable = false
   private(set) var isRecognizing = false

   init() {
      recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
      isAvailable = recognizer?.isAvailable ?? false
      NSLog("MouthPeace STT: SFSpeechRecognizer available=\(isAvailable)")
   }

   func requestAuthorization(completion: @escaping (Bool) -> Void) {
      SFSpeechRecognizer.requestAuthorization { status in
         let granted = status == .authorized
         NSLog("MouthPeace STT: authorization=\(status.rawValue) granted=\(granted)")
         DispatchQueue.main.async { completion(granted) }
      }
   }

   /// Start streaming recognition. Call `appendAudio` from the AVAudioEngine tap.
   func startRecognition(audioFormat: AVAudioFormat) {
      guard let recognizer, recognizer.isAvailable, !isRecognizing else { return }

      recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
      guard let request = recognitionRequest else { return }
      request.shouldReportPartialResults = true
      request.requiresOnDeviceRecognition = true
      request.taskHint = .dictation

      latestTranscription = nil
      isFinishing = false
      isRecognizing = true

      recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
         DispatchQueue.main.async {
            self?.handleRecognitionResult(result, error: error)
         }
      }

      NSLog("MouthPeace STT: recognition started")
   }

   /// Feed audio buffers from the AVAudioEngine tap.
   func appendAudio(_ buffer: AVAudioPCMBuffer) {
      recognitionRequest?.append(buffer)
   }

   private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
      if let result {
         latestTranscription = result.bestTranscription.formattedString
         if result.isFinal {
            finishRecognition(reason: "final")
         } else {
            onPartialResult?(result.bestTranscription.formattedString)
         }
      }
      if let error {
         NSLog("MouthPeace STT: error: \(error.localizedDescription)")
         if isFinishing {
            finishRecognition(reason: "error")
         }
      }
   }

   /// Stop recognition and deliver final result.
   func stopRecognition(completion: (() -> Void)? = nil) {
      guard isRecognizing else {
         completion?()
         return
      }

      finishCompletion = completion
      isFinishing = true
      recognitionRequest?.endAudio()

      let workItem = DispatchWorkItem { [weak self] in
         self?.finishRecognition(reason: "fallback")
      }
      finishWorkItem = workItem
      DispatchQueue.main.asyncAfter(deadline: .now() + finalizationFallbackDelay, execute: workItem)
   }

   private func finishRecognition(reason: String) {
      guard isRecognizing || isFinishing || finishCompletion != nil else { return }

      finishWorkItem?.cancel()
      finishWorkItem = nil

      let text = latestTranscription ?? ""
      if !text.isEmpty {
         NSLog(
            "MouthPeace STT: final transcription (\(reason), delay=\(Int(finalizationFallbackDelay * 1000))ms): '\(text)'"
         )
         onTranscription?(text)
      } else {
         NSLog("MouthPeace STT: no speech detected (\(reason))")
      }

      recognitionTask?.cancel()
      recognitionTask = nil
      recognitionRequest = nil
      latestTranscription = nil
      isRecognizing = false
      isFinishing = false

      let completion = finishCompletion
      finishCompletion = nil
      completion?()
   }
}
