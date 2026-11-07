// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PhraseLilt",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "PhraseLilt", targets: ["PhraseLilt"]),
               .executable(name: "SpeechProbe", targets: ["SpeechProbe"])],
    targets: [.target(name: "PracticeCore"),
              .executableTarget(name: "PhraseLilt", dependencies: ["PracticeCore"]),
              .executableTarget(name: "SpeechProbe", dependencies: ["PracticeCore"]),
              .testTarget(name: "PracticeCoreTests", dependencies: ["PracticeCore"]),
              .testTarget(name: "AppTests", dependencies: ["PhraseLilt"])]
)
