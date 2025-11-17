# Flutter 集成

这个目录包含 inferx-sdk 的 Flutter 插件和样例应用。

## 结构

```
flutter/
├── llx_flutter/           # Flutter 插件
│   ├── lib/               # Dart API
│   ├── android/           # Android 平台实现（Kotlin + MethodChannel）
│   ├── example/           # 样例应用
│   └── README.md          # 插件文档
└── README.md              # 本文件
```

## llx_flutter 插件

Flutter 插件，封装 inferx-sdk 的能力，提供 Dart API。

**平台支持**:
- ✅ Android (通过 llx-android)
- ⏳ iOS (待实现)

查看 [llx_flutter/README.md](llx_flutter/README.md) 了解详细信息。

## 样例应用

完整的聊天应用示例，展示如何使用 llx_flutter 插件。

**功能**:
- 加载和管理 GGUF 模型
- 流式文本生成
- 多 LoRA 适配器支持
- 基准测试
- Markdown 渲染

查看 [llx_flutter/example/README.md](llx_flutter/example/README.md) 了解详细信息。

## 快速开始

### 1. 构建 llx-android

```bash
cd ../android/llx-android
./gradlew assembleRelease
```

### 2. 运行样例应用

```bash
cd llx_flutter/example
flutter pub get
flutter run
```

### 3. 在你的项目中使用

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  llx_flutter:
    path: path/to/flutter/llx_flutter
```

在 `android/settings.gradle.kts` 中包含 llx-android：

```kotlin
include(':llx-android')
project(':llx-android').projectDir = File('path/to/android/llx-android')
```

## 开发

### 目录结构

```
llx_flutter/
├── lib/
│   ├── llx_flutter.dart              # 主入口
│   ├── llx_flutter_platform_interface.dart  # 平台接口
│   ├── llx_flutter_method_channel.dart      # MethodChannel 实现
│   └── src/
│       └── models.dart                # 数据模型
├── android/
│   ├── src/main/kotlin/com/inferx/llx_flutter/
│   │   └── LlxFlutterPlugin.kt       # Android 平台实现
│   ├── build.gradle                   # 构建配置
│   └── settings.gradle                # 包含 llx-android
└── example/
    ├── lib/
    │   └── main.dart                  # 样例应用
    └── android/
        └── settings.gradle.kts        # 包含 llx-android
```

### 架构

```
Flutter App (Dart)
      ↓
llx_flutter API (Dart)
      ↓
Platform Interface (Dart)
      ↓
MethodChannel
      ↓
LlxFlutterPlugin (Kotlin)
      ↓
llx-android (JNI)
      ↓
inferx-sdk (C++)
      ↓
llama.cpp
```

### 添加新功能

1. 在 `lib/llx_flutter.dart` 添加 Dart API
2. 在 `lib/llx_flutter_platform_interface.dart` 添加平台接口
3. 在 `lib/llx_flutter_method_channel.dart` 实现 MethodChannel 调用
4. 在 `android/.../LlxFlutterPlugin.kt` 实现 Android 平台代码

### 测试

```bash
cd llx_flutter
flutter test

# 集成测试
cd example
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/plugin_integration_test.dart
```

## 与 Android 样例的对比

| 功能 | Android (Kotlin) | Flutter (Dart) |
|------|-----------------|----------------|
| UI 框架 | Jetpack Compose | Flutter Widgets |
| 状态管理 | ViewModel | StatefulWidget |
| 文件选择 | ActivityResultContracts | file_picker |
| Markdown | Markwon | markdown_widget |
| 原生调用 | JNI | MethodChannel |
| 布局 | Column/Row/Box | Column/Row/Container |

## 常见问题

### Q: 如何调试 Android 平台代码？

A: 在 Android Studio 中打开 `example/android` 目录，设置断点并运行调试。

### Q: 为什么 iOS 还未支持？

A: iOS 平台需要：
1. 创建 llx-ios 模块（Swift/Objective-C）
2. 实现 FlutterPlugin
3. 配置 Podspec

### Q: 如何更新 llx-android？

A: 
1. 在 llx-android 中进行修改
2. 重新构建：`cd android/llx-android && ./gradlew assembleRelease`
3. 无需更改 Flutter 代码（如果 API 未变）

### Q: 插件性能如何？

A: MethodChannel 通信开销很小（微秒级），主要性能取决于：
- 模型推理速度（由 llama.cpp 决定）
- 设备性能
- 模型大小和量化方式

## 许可证

与 inferx-sdk 保持一致。

## 贡献

欢迎贡献！请：
1. Fork 项目
2. 创建功能分支
3. 提交 Pull Request

## 相关链接

- [inferx-sdk](../README.md)
- [llx-android](../android/llx-android/README.md)
- [Flutter 文档](https://flutter.dev/docs)
- [MethodChannel 文档](https://docs.flutter.dev/platform-integration/platform-channels)

