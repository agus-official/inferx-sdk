InferxLLMExample (SwiftUI)
==========================

运行步骤
1) 在 Xcode 打开本目录或上层仓库；确保已将 `ios/llx-ios/` 包添加为 Swift Package 依赖（Add Local… 选择 `Package.swift`）。
2) 应用 target 链接 `InferxLLMKit`（包会自动把 `InferxLLMKit` 暴露为库）。
3) 准备模型文件（.gguf），在真机上运行建议启用 Metal 支持的二进制；模拟器上可先用 CPU 路径二进制。
4) 运行后在文本框输入模型路径，点击“加载模型”，然后“初始化对话”“生成一步”。

注意
- 示例以最小可行 UI 演示加载/生成流程，真实应用可参考 `third_party/llama.cpp/examples/llama.swiftui` 的交互和并发结构进一步完善。


