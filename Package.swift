// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PyLabNative",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "PyLabNative", targets: ["PyLabNative"])],
    targets: [.executableTarget(name: "PyLabNative", path: ".", exclude: ["scripts", "docs", "CONTRIBUTING.md", "SECURITY.md", "LICENSING.md", "CHANGELOG.md", "requirements-test.txt", "README.md", "VALIDATION.md", "build", "dist", "Info.plist", "Examples", "tests"], sources: ["Sources"], resources: [.copy("Resources/kernel_bridge.py"), .copy("Resources/workspace_actions.py")])],
    swiftLanguageModes: [.v5]
)
