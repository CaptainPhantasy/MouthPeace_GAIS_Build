// swift-tools-version: 5.9
import PackageDescription

let package = Package(
   name: "MouthPeace",
   platforms: [.macOS(.v14)],
   targets: [
      .executableTarget(
         name: "MouthPeace",
         path: "Sources/MouthPeace",
         linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("SwiftUI"),
            .linkedFramework("Carbon"),
            .linkedFramework("AVFoundation"),
            .linkedFramework("Speech"),
            .linkedFramework("Network"),
         ]
      )
   ]
)
