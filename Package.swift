// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PhraseLilt",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "PhraseLilt", targets: ["PhraseLilt"]),
               .executable(name: "SpeechProbe", targets: ["SpeechProbe"])],
    dependencies: [.package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", revision: "b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2")],
    targets: [.target(name: "PracticeCore", dependencies: [.product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")]),
              .executableTarget(name: "PhraseLilt", dependencies: ["PracticeCore"]),
              .executableTarget(name: "SpeechProbe", dependencies: ["PracticeCore"]),
              .testTarget(name: "PracticeCoreTests", dependencies: ["PracticeCore"]),
              .testTarget(name: "AppTests", dependencies: ["PhraseLilt"])]
)
