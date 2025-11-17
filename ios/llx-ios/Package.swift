// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "InferxLLMKit",
    platforms: [
        .iOS(.v15), .macOS(.v12)
    ],
    products: [
        .library(name: "InferxLLMKit", targets: ["InferxLLMKit"])
    ],
    targets: [
        // Prebuilt llama.cpp from official release
        .binaryTarget(
            name: "llama",
            path: "Sources/InferxLLMNative/llama.xcframework"
        ),
        // C header-only bridge to expose llx.h to Swift
        .target(
            name: "CLLX",
            path: "Sources/CLLX",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        // Native bridge implemented in Objective-C++ and linked against prebuilt llama
        .target(
            name: "InferxLLMNative",
            dependencies: ["CLLX", "llama"],
            path: "Sources/InferxLLMNative",
            sources: ["llx_native.mm"],
            publicHeadersPath: "include",
            cxxSettings: [
                .define("GGML_USE_METAL", to: "1", .when(platforms: [.iOS])),
                .unsafeFlags(["-std=c++17"]) // llama headers are C++
            ]
        ),
        // Swift wrapper API
        .target(
            name: "InferxLLMKit",
            dependencies: ["CLLX", "InferxLLMNative"],
            path: "Sources/InferxLLMKit"
        ),
        .testTarget(
            name: "InferxLLMKitTests",
            dependencies: ["InferxLLMKit"],
            path: "Tests/InferxLLMKitTests"
        )
    ]
)


