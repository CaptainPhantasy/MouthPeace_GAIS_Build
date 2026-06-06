import AppKit
import Darwin

guard let echoSingletonLock = EchoSingletonLock.acquire() else {
   fputs("MouthPeace: another Echo instance is already running\n", stderr)
   exit(1)
}

_ = echoSingletonLock

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
