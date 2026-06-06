import Foundation

/// Local pronunciation fixes for phrases AVSpeechSynthesizer commonly reads wrong.
/// Keep this small and explicit: these substitutions affect audible output only,
/// not transcripts, stored events, or machine-facing API payloads.
enum SpeechPronunciation {
   private static let liveSession = "live session"
   private static let liveSessions = "live sessions"
   private static let liveSessionSpoken = "lyve session"
   private static let liveSessionsSpoken = "lyve sessions"

   static func prepareForSpeech(_ text: String) -> String {
      guard
         text.range(of: "live session", options: [.caseInsensitive, .diacriticInsensitive]) != nil
      else {
         return text
      }

      var result = ""
      result.reserveCapacity(text.count)
      var cursor = text.startIndex

      while cursor < text.endIndex {
         let remaining = cursor..<text.endIndex
         let singular = text.range(
            of: liveSession,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: remaining)
         let plural = text.range(
            of: liveSessions,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: remaining)

         let next: (Range<String.Index>, String)?
         switch (singular, plural) {
         case (let s?, let p?):
            if p.lowerBound == s.lowerBound {
               next = p.upperBound > s.upperBound ? (p, liveSessionsSpoken) : (s, liveSessionSpoken)
            } else {
               next = s.lowerBound < p.lowerBound ? (s, liveSessionSpoken) : (p, liveSessionsSpoken)
            }
         case (let s?, nil):
            next = (s, liveSessionSpoken)
         case (nil, let p?):
            next = (p, liveSessionsSpoken)
         case (nil, nil):
            result.append(contentsOf: text[cursor...])
            return result
         }

         guard let (range, replacement) = next else { break }
         result.append(contentsOf: text[cursor..<range.lowerBound])
         result.append(replacement)
         cursor = range.upperBound
      }

      return result
   }
}
