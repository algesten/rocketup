// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RocketUp", platforms: [.macOS("27.0")], products: [.executable(name: "RocketUp", targets: ["RocketUp"])], targets: [.executableTarget(name: "RocketUp", exclude: ["App.entitlements"])], swiftLanguageModes: [.v5])
