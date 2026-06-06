import Foundation

struct ConversationSettings: Codable, Equatable {
   var humanTurnSilenceSeconds: TimeInterval
   var bargeInThreshold: Float
   var bargeInRequiredFrames: Int
   var bargeInArmDelaySeconds: TimeInterval

   static let defaults = ConversationSettings(
      humanTurnSilenceSeconds: 2.0,
      bargeInThreshold: 0.12,
      bargeInRequiredFrames: 3,
      bargeInArmDelaySeconds: 1.6
   )

   var sanitized: ConversationSettings {
      ConversationSettings(
         humanTurnSilenceSeconds: Self.clamp(humanTurnSilenceSeconds, min: 0.2, max: 10.0),
         bargeInThreshold: Float(Self.clamp(Double(bargeInThreshold), min: 0.005, max: 0.5)),
         bargeInRequiredFrames: max(1, min(bargeInRequiredFrames, 40)),
         bargeInArmDelaySeconds: Self.clamp(bargeInArmDelaySeconds, min: 0.0, max: 5.0)
      )
   }

   var dictionary: [String: Any] {
      [
         "humanTurnSilenceSeconds": humanTurnSilenceSeconds,
         "bargeInThreshold": bargeInThreshold,
         "bargeInRequiredFrames": bargeInRequiredFrames,
         "bargeInArmDelaySeconds": bargeInArmDelaySeconds,
      ]
   }

   init(
      humanTurnSilenceSeconds: TimeInterval,
      bargeInThreshold: Float,
      bargeInRequiredFrames: Int,
      bargeInArmDelaySeconds: TimeInterval
   ) {
      self.humanTurnSilenceSeconds = humanTurnSilenceSeconds
      self.bargeInThreshold = bargeInThreshold
      self.bargeInRequiredFrames = bargeInRequiredFrames
      self.bargeInArmDelaySeconds = bargeInArmDelaySeconds
   }

   init(dictionary: [String: Any], fallback: ConversationSettings) throws {
      self.humanTurnSilenceSeconds = try Self.doubleValue(
         dictionary["humanTurnSilenceSeconds"], name: "humanTurnSilenceSeconds",
         fallback: fallback.humanTurnSilenceSeconds)
      self.bargeInThreshold = Float(
         try Self.doubleValue(
            dictionary["bargeInThreshold"], name: "bargeInThreshold",
            fallback: Double(fallback.bargeInThreshold)))
      self.bargeInRequiredFrames = try Self.intValue(
         dictionary["bargeInRequiredFrames"], name: "bargeInRequiredFrames",
         fallback: fallback.bargeInRequiredFrames)
      self.bargeInArmDelaySeconds = try Self.doubleValue(
         dictionary["bargeInArmDelaySeconds"], name: "bargeInArmDelaySeconds",
         fallback: fallback.bargeInArmDelaySeconds)
      self = sanitized
   }

   private static func doubleValue(_ value: Any?, name: String, fallback: Double) throws -> Double {
      guard let value else { return fallback }
      if let double = value as? Double { return double }
      if let int = value as? Int { return Double(int) }
      throw ToolError.invalidParams("'\(name)' must be a number")
   }

   private static func intValue(_ value: Any?, name: String, fallback: Int) throws -> Int {
      guard let value else { return fallback }
      if let int = value as? Int { return int }
      throw ToolError.invalidParams("'\(name)' must be an integer")
   }

   private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
      Swift.max(lower, Swift.min(value, upper))
   }
}

enum ConversationSettingsStore {
   private static let key = "MouthPeace.ConversationSettings.v1"

   private static var persistenceDisabled: Bool {
      ProcessInfo.processInfo.environment["MOUTHPEACE_DISABLE_SETTINGS_PERSISTENCE"] == "1"
   }

   static func load() -> ConversationSettings {
      if persistenceDisabled { return .defaults }
      guard let data = UserDefaults.standard.data(forKey: key),
         let decoded = try? JSONDecoder().decode(ConversationSettings.self, from: data)
      else {
         return .defaults
      }
      return decoded.sanitized
   }

   static func save(_ settings: ConversationSettings) {
      if persistenceDisabled { return }
      guard let data = try? JSONEncoder().encode(settings.sanitized) else { return }
      UserDefaults.standard.set(data, forKey: key)
   }
}
