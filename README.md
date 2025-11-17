<h1 align="center">InferX</h1>
<p align="center"><b>Private On‑device LLM · Cross‑platform Inference SDK · Zero Cloud</b></p>
<p align="center"><i>Powered by <b>llama.cpp</b> · Lightweight • Fast • Extensible</i></p>

<p align="center">
  <a href="#license"><img alt="License" src="https://img.shields.io/badge/License-Apache%202.0-blue"></a>
  <a href="#platforms"><img alt="Android" src="https://img.shields.io/badge/Android-✓-3DDC84?logo=android&logoColor=white"></a>
  <a href="#platforms"><img alt="iOS" src="https://img.shields.io/badge/iOS-✓-000000?logo=apple&logoColor=white"></a>
  <a href="#platforms"><img alt="Windows" src="https://img.shields.io/badge/Windows-✓-0078D6?logo=windows&logoColor=white"></a>
  <a href="#platforms"><img alt="macOS" src="https://img.shields.io/badge/macOS-✓-000000?logo=apple&logoColor=white"></a>
  <a href="#platforms"><img alt="Linux" src="https://img.shields.io/badge/Linux-✓-FCC624?logo=linux&logoColor=black"></a>
  <br/>
  <a href="#install"><img alt="CMake" src="https://img.shields.io/badge/CMake-3.20%2B-064F8C?logo=cmake&logoColor=white"></a>
  <img alt="C++" src="https://img.shields.io/badge/C%2B%2B-17-00599C?logo=c%2B%2B&logoColor=white">
  <img alt="Kotlin" src="https://img.shields.io/badge/Kotlin-Android-7F52FF?logo=kotlin&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.8%2B-FA7343?logo=swift&logoColor=white">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.3%2B-02569B?logo=flutter&logoColor=white">
  <img alt="Backend" src="https://img.shields.io/badge/Backend-llama.cpp-2C3E50">
</p>

<p align="center">
  <a href="docs/README.zh-CN.md">中文文档</a>
</p>

---

## 📚 Table of Contents
- [Why InferX](#why)
- [Updates](#updates)
- [Features](#features)
- [Architecture](#arch)
- [Platforms](#platforms)
- [Install & Build](#install)
- [Quickstart](#quickstart)
- [Examples](#examples)
- [Benchmarks](#benchmarks)
- [Roadmap](#roadmap)
- [FAQ](#faq)
- [Contributing](#contrib)
- [License](#license)

---

## <a name="why"></a>✨ Why InferX
- 🔒 **Privacy‑first**: fully offline, data never leaves the device.
- ⚡️ **Low‑latency streaming**: token‑by‑token output with smart UTF‑8 assembly.
- 🧩 **Stackable LoRA**: load multiple adapters, tune scales dynamically.
- 🔌 **OpenAI‑compatible**: Chat Completions with tools/tool_choice and sampling controls.
- 📦 **Unified C interface**: one `llx.h` for desktop and mobile, wrapped for native and Flutter.
- 🧱 **Production‑ready samples**: Android AAR, iOS Swift Package, CLI/Agent, Flutter plugin and apps.

---

## <a name="updates"></a>🆕 Updates
- 2025‑10: Initial public release and multi‑platform samples.

---

## <a name="features"></a>💡 Features
- **Streaming/non‑streaming generation** with KV reuse/clear and UTF‑8 safe chunks.
- **OpenAI‑compatible Chat API**: `llx_chat_complete_json` supports messages/tools/tool_choice/temperature/top_p/top_k/max_tokens.
- **Multi‑LoRA stacking**: `llx_session_add_lora`, `_update_lora_scale`, `_remove_lora`, `_clear_lora`.
- **Unified C API**: backend init, model/session lifecycle, stepwise generation, benchmarking.
- **Comprehensive samples**: CLI chat and local Agent, Android AAR + app, iOS SPM + app, Flutter plugin + app.

---

## <a name="arch"></a>🧱 Architecture
Layers from top to bottom:
- Core: `llama.cpp`‑based inference with chat templates and tool‑calling parsing.
- C interface: unified `llx.h` across OS/languages.
- Bindings: Android (JNI/Kotlin), iOS (ObjC++/Swift), Flutter (MethodChannel).
- Tooling: local benchmarks (`llx_bench`), LoRA management, sample apps.

---

## <a name="platforms"></a>🧭 Platforms
| OS/Framework | Native | Flutter | Notes |
|---|---|---|---|
| Android 8+ | ✅ | ✅ | CPU backend; ABI: arm64‑v8a; Vulkan/NNAPI planned |
| iOS 15+ | ✅ | ✅ | Integrate via Swift Package; Metal depends on binaries; CoreML planned |
| Windows 10+ | ✅ | ⏳ | CPU path; DirectML planned |
| macOS 12+ | ✅ | ⏳ | Metal/Accelerate (via backend) |
| Linux (x86/arm) | ✅ | ⏳ | CPU path; BLAS optional per llama.cpp docs |

---

## <a name="install"></a>⚙️ Install & Build

### Prerequisites
- CMake 3.20+, C/C++17 toolchains (Xcode/CLT on macOS; VS 2022 x64 on Windows).
- Optional: BLAS on Linux as per llama.cpp docs.

### Desktop (macOS/Linux)
```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

### Desktop (Windows, VS 2022)
```bash
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release -m
```

> Binaries will be in `build/` (e.g., `llx-cli`, `llx-agent`).

### Android (AAR and sample app)
1) Build the native AAR:
```bash
cd android/llx-android
./gradlew assembleRelease
```
Artifact: `android/llx-android/build/outputs/aar/llx-android-release.aar`

2) Run the sample app:
- Open `android/` in Android Studio and run `llx-example/app`; or via CLI:
```bash
cd android
./gradlew :llx-example:app:assembleDebug
```
> Current ABI is `arm64-v8a`; use an arm64 emulator or device.

### iOS (Swift Package and sample)
- Add `ios/llx-ios` as a local Swift Package in Xcode (Add Local → select `Package.swift`).
- Place prebuilt native binaries (e.g., `llama.xcframework`) into `ios/llx-ios/Sources/InferxLLMNative/` and ensure linkage in `Package.swift` (sample `binaryTarget` provided).
- See `ios/Example/InferxLLMExample/` for the sample app.

### Flutter (plugin and example)
- Plugin: `flutter/llx_flutter` (Android supported, iOS WIP).
- Add as a path dependency in your Flutter app:
```yaml
dependencies:
  llx_flutter:
    path: ../../flutter/llx_flutter
```
- Run the example:
```bash
cd flutter/llx_flutter/example
flutter pub get
flutter run
```
> Build `llx-android` first on Android.

---

## <a name="quickstart"></a>🚀 Quickstart

### CLI (`llx-cli`)
- Interactive chat:
```bash
./build/llx-cli --model /path/to/model.gguf --ctx 8192 --nlen 1024
```
- One‑shot JSON (OpenAI compatible):
```bash
./build/llx-cli --model /path/to/model.gguf --json ./request.json
```
- Multiple LoRA with per‑adapter scale:
```bash
./build/llx-cli --model /path/base.gguf \
  --lora /path/adapter1.gguf:0.2 \
  --lora /path/adapter2.gguf:0.4
```

### Local Agent (function calling demo)
```bash
./build/llx-agent --model /path/to/model.gguf --ctx 16384 --max_tokens 1024 --temp 0.7 --top_p 0.9 --top_k 40
```

### Android (Kotlin)
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

### iOS (Swift)
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

### Flutter (Dart)
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

## <a name="examples"></a>📦 Examples
- `example/cli.cpp`: CLI chat with JSON one‑shot and multi‑LoRA stacking.
- `example/agent.cpp`: Local function‑calling Agent, prints request/response JSON.
- `android/llx-android`: AAR + JNI binding.
- `android/llx-example`: Minimal native sample app with streaming UI.
- `ios/llx-ios`: Swift Package (CLLX/Native/Kit layers).
- `ios/Example/InferxLLMExample`: SwiftUI sample app.
- `flutter/llx_flutter`: Flutter plugin and example app (iOS in progress).

---

## <a name="benchmarks"></a>📈 Benchmarks
`llx_bench` helps measure prefill (pp) and generate (tg) throughput. Unified scripts and comparison tables will be added.

---

## <a name="roadmap"></a>🗺️ Roadmap
- [x] Unified Session API (streaming/non‑streaming)
- [x] Android AAR + native sample
- [x] iOS Swift Package + native sample
- [x] Flutter plugin (Android) + sample
- [ ] Flutter (iOS)
- [ ] Vulkan/NNAPI/CoreML backends
- [ ] HarmonyOS support

---

## <a name="faq"></a>❓ FAQ
**Q: Multi‑LoRA sometimes degrades quality?**
Layer conflicts or improper scales may cause drift. Try lower scales, scenario‑specific adapters, or offline distillation/merging.

---

## <a name="contrib"></a>🤝 Contributing
PRs and issues are welcome. Please read this README and submodule READMEs (Android/iOS/Flutter), run the samples on your target platform, then file improvements or bug reports.

---

## <a name="license"></a>📄 License
Apache‑2.0

<p align="center">⭐️ If you find InferX useful, please give it a star! ⭐️</p>