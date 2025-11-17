llx-android
===========

Android 原生库（AAR），提供对 inferx-sdk 的 Kotlin 封装。

构建
----

```
cd android/llx-android
./gradlew assembleRelease
```

产物：build/outputs/aar/llx-android-release.aar

使用
----

- 复制或下载 .gguf 模型到应用可读路径
- 依赖 AAR（本地或 mavenLocal()）

Kotlin 示例：

```
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

ABI
---

- 目前仅 arm64-v8a，如需更多 ABI，可在 build.gradle.kts 的 ndk.abiFilters 中添加。

性能选项
------

- 初版使用 CPU；若需 Vulkan，请在 CMakeLists.txt 中开启 GGML_VULKAN 并按 llama.cpp 文档打包 Vulkan 资源。

