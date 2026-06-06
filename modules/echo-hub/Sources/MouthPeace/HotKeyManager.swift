import Foundation
import Carbon.HIToolbox

/// Wraps Carbon's `RegisterEventHotKey` API for push-to-talk.
/// Fires `onPress` when the hotkey is pressed, `onRelease` when released.
/// Carbon is the only supported path for app-global hotkeys on macOS.
final class HotKeyManager {

    /// Called on main thread when hotkey is pressed down.
    var onPress: (() -> Void)?
    /// Called on main thread when hotkey is released.
    var onRelease: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = OSType(0x4D43544C) // 'MCTL'
    private var nextID: UInt32 = 1

    init() {
        installHandler()
    }

    deinit {
        unregister()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    @discardableResult
    func register(_ hk: HotKey) -> Bool {
        unregister()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: nextID)
        nextID &+= 1

        let status = RegisterEventHotKey(
            hk.keyCode,
            hk.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        NSLog("MouthPeace: RegisterEventHotKey(keyCode=\(hk.keyCode), mods=\(hk.modifiers)) → status=\(status)")
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    // MARK: - Event handler

    private func installHandler() {
        // Register for both pressed and released events
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased))
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { (_, eventRef, userData) -> OSStatus in
            guard let userData, let eventRef else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

            var eventKind: UInt32 = 0
            GetEventParameter(eventRef,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeUInt32),
                              nil, 0, nil, nil)
            eventKind = GetEventKind(eventRef)

            DispatchQueue.main.async {
                if eventKind == UInt32(kEventHotKeyPressed) {
                    NSLog("MouthPeace: HotKey PRESSED (PTT start)")
                    manager.onPress?()
                } else if eventKind == UInt32(kEventHotKeyReleased) {
                    NSLog("MouthPeace: HotKey RELEASED (PTT stop)")
                    manager.onRelease?()
                }
            }
            return noErr
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            2,
            &specs,
            selfPtr,
            &eventHandler
        )
        NSLog("MouthPeace: InstallEventHandler (press+release) → status=\(handlerStatus)")
    }
}
