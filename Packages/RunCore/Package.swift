// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "RunCore", platforms: [.iOS("18.5"), .watchOS("11.5"), .macOS(.v14)],
    products: [.library(name: "RunCore", targets: ["RunCore"])],
    targets: [.target(name: "RunCore"), .testTarget(name: "RunCoreTests", dependencies: ["RunCore"])])
