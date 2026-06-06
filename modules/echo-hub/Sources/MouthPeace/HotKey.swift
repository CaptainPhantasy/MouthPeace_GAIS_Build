import AppKit
import Carbon.HIToolbox
import Foundation

/// Codable hotkey binding: a key code plus a Carbon-style modifier mask.
/// Modifier values are the Carbon flags (`cmdKey`, `shiftKey`, etc.) so they can be
/// passed directly to `RegisterEventHotKey` without remapping.
struct HotKey: Codable, Equatable {
   /// Virtual key code (e.g. `kVK_Space`).
   var keyCode: UInt32
   /// Bitmask of Carbon modifier flags (`cmdKey | shiftKey | optionKey | controlKey`).
   var modifiers: UInt32

   static let defaultBinding = HotKey(
      keyCode: UInt32(kVK_Space),
      modifiers: UInt32(controlKey | optionKey | cmdKey)
   )

   /// Human-readable label like "⌃⌥⌘Space" for the popover UI.
   var displayString: String {
      var parts: [String] = []
      if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
      if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
      if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
      if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
      parts.append(Self.keyName(for: keyCode))
      return parts.joined()
   }

   private static func keyName(for keyCode: UInt32) -> String {
      // Cover common keys; fall back to a hex code for unusual ones so we never crash.
      switch Int(keyCode) {
      case kVK_Space: return "Space"
      case kVK_Return: return "Return"
      case kVK_Tab: return "Tab"
      case kVK_Escape: return "Esc"
      case kVK_Delete: return "Delete"
      case kVK_ForwardDelete: return "FwdDel"
      case kVK_LeftArrow: return "←"
      case kVK_RightArrow: return "→"
      case kVK_UpArrow: return "↑"
      case kVK_DownArrow: return "↓"
      case kVK_F1: return "F1"
      case kVK_F2: return "F2"
      case kVK_F3: return "F3"
      case kVK_F4: return "F4"
      case kVK_F5: return "F5"
      case kVK_F6: return "F6"
      case kVK_F7: return "F7"
      case kVK_F8: return "F8"
      case kVK_F9: return "F9"
      case kVK_F10: return "F10"
      case kVK_F11: return "F11"
      case kVK_F12: return "F12"
      default:
         // Translate via the current keyboard layout for letter/number keys.
         if let name = Self.charForKeyCode(UInt16(keyCode)) {
            return name.uppercased()
         }
         return String(format: "0x%02X", keyCode)
      }
   }

   private static func charForKeyCode(_ keyCode: UInt16) -> String? {
      let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
      guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
      else {
         return nil
      }
      let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPtr).takeUnretainedValue() as Data
      var deadKeyState: UInt32 = 0
      var chars = [UniChar](repeating: 0, count: 4)
      var length = 0
      let status = layoutData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OSStatus in
         guard let base = raw.baseAddress else { return -1 }
         let layoutPtr = base.assumingMemoryBound(to: UCKeyboardLayout.self)
         return UCKeyTranslate(
            layoutPtr,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
         )
      }
      guard status == noErr, length > 0 else { return nil }
      return String(utf16CodeUnits: chars, count: length)
   }
}

/// Converts AppKit's `NSEvent.modifierFlags` into Carbon's modifier bitmask.
func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
   var m: UInt32 = 0
   if flags.contains(.command) { m |= UInt32(cmdKey) }
   if flags.contains(.shift) { m |= UInt32(shiftKey) }
   if flags.contains(.option) { m |= UInt32(optionKey) }
   if flags.contains(.control) { m |= UInt32(controlKey) }
   return m
}
