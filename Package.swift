// swift-tools-version: 6.0
import PackageDescription

// The same sources also belong to the iOS target. This package lets the domain
// logic and persistence tests run without an iOS simulator or third-party tools.
let package = Package(
    name: "MealPlannerCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MealPlannerCore", targets: ["MealPlannerCore"])],
    targets: [
        .target(name: "MealPlannerCore", path: "Recipe Maker/Recipe Maker/Core",
                resources: [.process("Resources")], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "MealPlannerCoreTests", dependencies: ["MealPlannerCore"],
                    path: "Recipe Maker/Recipe MakerTests", exclude: ["Fixtures"])
    ],
    swiftLanguageModes: [.v5]
)
