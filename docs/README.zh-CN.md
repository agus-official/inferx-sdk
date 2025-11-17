<h1 align="center">InferX</h1>
<p align="center"><b>私有本地 LLM 推理 · 统一跨平台 SDK · 零云依赖</b></p>
<p align="center"><i>Powered by <b>llama.cpp</b> · 轻量、快速、可扩展</i></p>

---

## 📚 目录
- [为什么选择 InferX](#why)
- [更新日志](#updates)
- [特性](#features)
- [架构](#arch)
- [平台支持](#platforms)
- [安装与构建](#install)
- [快速上手](#quickstart)
- [示例](#examples)
- [基准测试](#benchmarks)
- [路线图](#roadmap)
- [FAQ](#faq)
- [参与贡献](#contrib)
- [许可协议](#license)

---

## <a name="why"></a>✨ 为什么选择 InferX
- 🔒 **隐私优先**：完全本地推理，数据绝不出端。
- ⚡️ **极速流式**：逐 token 输出，智能 UTF‑8 拼接，低延迟直达界面。
- 🧩 **LoRA 叠加**：原生支持多 LoRA 并行叠加与动态 scale 管理。
- 🔌 **OpenAI 兼容**：内置 Chat Completions + function calling（tools/tool_choice）。
- 📦 **统一 C 接口**：一个 `llx.h` 覆盖桌面与移动，原生/Flutter 统一封装。
- 🧱 **跨平台落地**：Android AAR、iOS Swift Package、CLI/Agent、Flutter 插件与示例齐备。

---

## <a name="updates"></a>🆕 更新日志
- 2025-10：初始化公开版本与多端示例整理。

---

## <a name="features"></a>💡 特性
- **流式/非流式生成**：逐 token 输出，智能 UTF‑8 片段拼接；KV 缓存可复用/清理。
- **OpenAI 兼容 Chat API**：`llx_chat_complete_json` 覆盖 messages/tools/tool_choice/temperature/top_p/top_k/max_tokens。
- **多 LoRA 叠加**：`llx_session_add_lora / _update_lora_scale / _remove_lora / _clear_lora` 灵活组合与热调参。
- **统一 C 接口**：`include/llx.h` 提供后端初始化、模型/会话生命周期、步进式生成、基准等。
- **示例齐全**：CLI 聊天与本地 Agent、Android AAR + 示例、iOS Swift Package + 示例、Flutter 插件 + 示例。

---

## <a name="arch"></a>🧱 架构
自上而下：高层封装 → 平台绑定 → 工具链 → Backend Core。
- Core：基于 `llama.cpp`，提供通用推理能力（含 chat 模板与工具调用解析）。
- C 接口：`llx.h` 统一暴露 API，跨 OS/语言一致。
- 绑定层：Android（JNI/Kotlin）、iOS（ObjC++/Swift）、Flutter（MethodChannel）。
- 工具链：本地基准（`llx_bench`）、LoRA 管理、示例工程。

---

## <a name="platforms"></a>🧭 平台支持
| OS/Framework | 原生 | Flutter | 说明 |
|---|---|---|---|
| Android 8+ | ✅ | ✅ | 现支持 CPU；ABI：arm64-v8a；Vulkan/NNAPI 规划中 |
| iOS 15+ | ✅ | ⏳ | 以 Swift Package 集成；Metal 支持取决于二进制；CoreML 规划中 |
| Windows 10+ | ✅ | ✅ | CPU 路径；DirectML 规划中 |
| macOS 12+ | ✅ | ✅ | Metal/Accelerate（透传自后端）|
| Linux (x86/arm) | ✅ | ✅ | CPU 路径；BLAS 可按 llama.cpp 文档自行配置 |

---

## <a name="install"></a>⚙️ 安装与构建

### 依赖
- CMake 3.20+、C/C++17 工具链（macOS 建议 Xcode/Command Line Tools；Windows 使用 VS 2022 x64）。
- 可选：Linux 根据 llama.cpp 文档启用 BLAS 以提升性能。

### Desktop（macOS/Linux）
```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

### Desktop（Windows，VS 2022）
```bash
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release -m
```

> 构建完成后，二进制位于 `build/`（如 `llx-cli`、`llx-agent`）。

### Android（AAR 与示例 App）
1) 构建原生库（AAR）：
```bash
cd android/llx-android
./gradlew assembleRelease
```
产物：`android/llx-android/build/outputs/aar/llx-android-release.aar`

2) 运行示例 App：
- 用 Android Studio 打开 `android/` 目录，直接运行 `llx-example/app`；或命令行：
```bash
cd android
./gradlew :llx-example:app:assembleDebug
```
> 当前 ABI 为 `arm64-v8a`，请使用 arm64 模拟器或真机。

### iOS（Swift Package 与示例）
- 打开 Xcode，将本仓库的 `ios/llx-ios` 作为本地 Swift Package（Add Local → 选择 `Package.swift`）。
- 在 `ios/llx-ios/Sources/InferxLLMNative/` 放置预构建的 `llama.xcframework` 等原生二进制，并确保 `Package.swift` 已链接（仓库已包含 `binaryTarget` 与桥接目标示例）。
- 示例工程见 `ios/Example/InferxLLMExample/`，按其 README 步骤运行。

### Flutter（插件与示例）
- 插件：`flutter/llx_flutter`（Android 已支持，iOS 进行中）。
- 在你的 Flutter app 中以 path 方式依赖：
```yaml
dependencies:
  llx_flutter:
    path: ../../flutter/llx_flutter
```
- 运行样例：
```bash
cd flutter/llx_flutter/example
flutter pub get
flutter run
```
> Android 侧需先构建 `llx-android`，见上文。

---

## <a name="quickstart"></a>🚀 快速上手

### 命令行（llx-cli）
- 交互式对话：
```bash
./build/llx-cli --model /path/to/model.gguf --ctx 8192 --nlen 1024
```
- JSON 一次性请求（OpenAI 兼容）：
```bash
./build/llx-cli --model /path/to/model.gguf --json ./request.json
```
- 叠加多个 LoRA（可分别设置 scale）：
```bash
./build/llx-cli --model /path/base.gguf \
  --lora /path/adapter1.gguf:0.2 \
  --lora /path/adapter2.gguf:0.4
```

### 本地 Agent（Function Calling 演示）
```bash
./build/llx-agent --model /path/to/model.gguf --ctx 16384 --max_tokens 1024 --temp 0.7 --top_p 0.9 --top_k 40
```

### Android（Kotlin 片段）
```kotlin
LLX.nativeInitBackend()
val model = LLX.nativeModelLoad(modelPath)
val sess = LLX.nativeSessionCreate(model, 8192, 0)
LLX.nativeSessionInitFromText(sess, "你好", true, 1024)
while (true) {
    val r = LLX.nativeSessionStep(sess, 1024)
    print(r.text)
    if (r.finished) break
}
LLX.nativeSessionFree(sess)
LLX.nativeModelFree(model)
LLX.nativeFreeBackend()
```

### iOS（Swift 片段）
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

### Flutter（Dart 片段）
```dart
final llx = LlxFlutter();
await llx.initBackend();
final model = await llx.modelLoad('/path/to/model.gguf');
final session = await llx.sessionCreate(model, nCtx: 8192, nThreads: 0);
final messagesJson = '[{"role":"user","content":"你好"}]';
await llx.sessionInitFromMessagesJson(session, messagesJson);
while (true) {
  final r = await llx.sessionStep(session);
  print(r.text);
  if (r.finished) break;
}
```

---

## <a name="examples"></a>📦 示例
- `example/cli.cpp`：命令行聊天，支持 JSON 请求与多 LoRA 叠加。
- `example/agent.cpp`：本地 Agent（function calling）演示，展示请求/响应 JSON。
- `android/llx-android`：AAR 原生库与 JNI 封装。
- `android/llx-example`：最小原生示例 App，流式输出到界面。
- `ios/llx-ios`：Swift Package（CLLX/Native/Kit 三层封装）。
- `ios/Example/InferxLLMExample`：SwiftUI 示例应用。
- `flutter/llx_flutter`：Flutter 插件与示例应用（iOS 侧开发中）。

---

## <a name="benchmarks"></a>📈 基准测试
`llx.h` 提供 `llx_bench`，用于快速评估预填充（pp）与生成（tg）吞吐；后续将补充统一脚本与更多设备/模型对比。

---

## <a name="roadmap"></a>🗺️ 路线图
- [x] 统一 Session API（流式/非流式）
- [x] Android AAR 与原生示例
- [x] iOS Swift Package 与原生示例
- [x] Flutter 插件（Android）与示例
- [ ] Flutter（iOS）
- [ ] Vulkan/NNAPI/CoreML 后端增强
- [ ] HarmonyOS 支持

---

## <a name="faq"></a>❓ FAQ
**Q: 多 LoRA 叠加有时效果波动？**
可能存在层级冲突或缩放不当。建议拉低部分 scale、按场景拆分，或进行离线蒸馏/融合。

---

## <a name="contrib"></a>🤝 参与贡献
欢迎 PR/Issue！建议先阅读本 README 与各子模块 README（Android/iOS/Flutter），按对应平台指南运行示例后提交问题或改进建议。

---

## <a name="license"></a>📄 许可协议
Apache-2.0

<p align="center">⭐️ 如果觉得有用，欢迎点亮 Star！⭐️</p>


