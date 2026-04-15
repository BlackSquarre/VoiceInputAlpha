// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            path: "Sources/VoiceInput",
            exclude: ["Info.plist", "AppIcon.icns"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/VoiceInput/Info.plist",
                ]),
            ]
        ),
    ]
)
