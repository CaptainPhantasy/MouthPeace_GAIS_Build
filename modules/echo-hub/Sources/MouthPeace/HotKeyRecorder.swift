import AppKit
import SwiftUI

/// Manages the armed/monitor state as a reference type so closures work correctly.
final class RecorderState: ObservableObject {
    @Published var armed = false
    var onCapture: ((HotKey) -> Void)?
    private var monitor: Any?

    func toggle() {
        if armed { disarm() } else { arm() }
    }

    func arm() {
        disarm()
        armed = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.armed else { return event }
            let mods = carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { return event }
            let newHK = HotKey(keyCode: UInt32(event.keyCode), modifiers: mods)
            DispatchQueue.main.async {
                self.onCapture?(newHK)
                self.disarm()
            }
            return nil
        }
    }

    func disarm() {
        armed = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    deinit { disarm() }
}

/// Pure SwiftUI hotkey recorder. Click to arm, press a key combo with a modifier to set.
struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey
    @StateObject private var recorder = RecorderState()

    var body: some View {
        Button(action: { recorder.toggle() }) {
            Text(recorder.armed ? "Press shortcut…" : hotKey.displayString)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(recorder.armed ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recorder.armed ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onAppear {
            let binding = $hotKey
            recorder.onCapture = { newHK in
                binding.wrappedValue = newHK
            }
        }
        .onDisappear { recorder.disarm() }
    }
}
