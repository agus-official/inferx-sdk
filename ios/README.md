InferxLLMKit (iOS Swift Package)
================================

本目录包含可独立发布的 Swift Package：`InferxLLMKit`。它对底层 C 接口 `llx.h` 进行 Swift 封装，并预留原生二进制（`xcframework`）放置位置。

目录结构
- `llx-ios/Package.swift`: 包定义
- `llx-ios/Sources/CLLX`: C 头桥接（公开 `llx.h`）
- `llx-ios/Sources/InferxLLMNative`: 原生桥接（链接 `llama.xcframework`）
- `llx-ios/Sources/InferxLLMKit`: Swift 封装层（`InferxModel`/`InferxSession`）
- `llx-ios/Tests/InferxLLMKitTests`: 预留测试
- `Example/InferxLLMExample`: SwiftUI 原生示例工程

集成步骤（应用中引用）
1) 在 Xcode 的 Package Dependencies 中添加本仓库的 `ios/llx-ios` 目录（Add Local… 直接选择该目录或其 `Package.swift`）。
2) 将你构建好的底层二进制（如 `libllama.xcframework`、`libinferx_llm.xcframework`）放入 `Sources/InferxLLMNative/`，并把 `Package.swift` 的 `InferxLLMNative` 改为 `.binaryTarget`（或在 App 侧直接链接这些二进制并保留占位目标）。

示例替换（片段）
```swift
.binaryTarget(
    name: "InferxLLMNative",
    path: "Sources/InferxLLMNative/YourNative.xcframework"
)
```

Swift 使用示例
```swift
import InferxLLMKit

let model = try InferxModel(path: "/path/to/model.gguf")
let sess = try model.createSession()
try sess.initFromText("Hello", formatChat: true, maxLen: 512)
while true {
    let (chunk, finished) = try sess.step(maxLen: 512)
    print(chunk, terminator: "")
    if finished { break }
}
```

注意
- 模拟器通常不支持 Metal；如需在模拟器跑，请提供 CPU 路径二进制。
- 真实设备建议提供含 Metal/Accelerate 的 `xcframework`。
- 错误可通过 Swift 抛出的 `NSError`（内部来自 `llx_last_error()`）查看。

示例应用
- 见 `Example/InferxLLMExample/`，打开 `InferxLLMExample.xcodeproj`，按 README 指引将本包加入该工程后即可运行。


