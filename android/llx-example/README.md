llx-example
===========

最小原生示例 App，依赖同仓库下的 `llx-android` 模块，点击按钮后加载 `filesDir/model.gguf` 并执行一次推理，将输出流式追加到界面。

运行
----
1) 将模型文件 `model.gguf` 放到设备或模拟器的 `Android/data/com.inferx.example/files/` 对应目录（或通过 `adb push` 到 App 的 `filesDir`）。
2) 用 Android Studio 打开仓库的 `android/` 目录（包含 `settings.gradle.kts`），选择 `app` 运行。
   - 如需命令行打包：在 `android/` 下执行 `./gradlew :llx-example:app:assembleDebug`。

说明
----
- 示例通过模块依赖 `implementation(project(":llx-android"))` 使用本地 AAR/so，便于联调。
- 仅 arm64-v8a；请使用 arm64 模拟器或真机。

