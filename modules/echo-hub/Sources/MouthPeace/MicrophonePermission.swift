import AVFoundation
import AppKit
import Combine

/// Thin wrapper around AVCaptureDevice authorization for audio.
/// Publishes the current status so SwiftUI can react to changes.
@MainActor
final class MicrophonePermission: ObservableObject {
    enum Status {
        case notDetermined
        case denied
        case restricted
        case authorized

        init(_ raw: AVAuthorizationStatus) {
            switch raw {
            case .notDetermined: self = .notDetermined
            case .denied:        self = .denied
            case .restricted:    self = .restricted
            case .authorized:    self = .authorized
            @unknown default:    self = .denied
            }
        }
    }

    @Published private(set) var status: Status

    init() {
        self.status = Status(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func refresh() {
        status = Status(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func request() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            self.status = granted ? .authorized : .denied
        }
    }

    /// Opens System Settings → Privacy & Security → Microphone.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
