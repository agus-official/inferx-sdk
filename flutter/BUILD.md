# Flutter 构建指南

本文档介绍如何构建和运行 inferx-sdk 的 Flutter 插件和样例应用。

## 前置条件

### 1. 开发环境

- **Flutter SDK**: 3.9.2 或更高版本
- **Android Studio**: 最新稳定版
- **Android SDK**: API 24+ (Android 7.0+)
- **NDK**: r25 或更高版本

### 2. 验证环境

```bash
flutter doctor
```

确保以下项目都有绿色的勾：
- Flutter SDK
- Android toolchain
- Android Studio

## 构建步骤

### 步骤 1: 构建 llx-android 模块

首先需要构建底层的 Android 原生模块：

```bash
cd android/llx-android
./gradlew assembleRelease
```

输出产物：`android/llx-android/build/outputs/aar/llx-android-release.aar`

### 步骤 2: 获取 Flutter 依赖

```bash
cd flutter/llx_flutter
flutter pub get

cd example
flutter pub get
```

### 步骤 3: 运行样例应用

#### 使用命令行

```bash
cd flutter/llx_flutter/example
flutter run
```

#### 使用 Android Studio / VS Code

1. 打开 `flutter/llx_flutter/example` 目录
2. 连接 Android 设备或启动模拟器
3. 点击运行按钮

### 步骤 4: 准备模型文件

1. 下载一个 GGUF 格式的模型文件
2. 推荐使用小模型进行测试（如 Qwen2.5-0.5B）
3. 在应用中点击"加载 GGUF"按钮选择模型

## 目录结构

```
flutter/
├── llx_flutter/                    # Flutter 插件
│   ├── lib/                        # Dart API
│   │   ├── llx_flutter.dart        # 主 API
│   │   ├── llx_flutter_platform_interface.dart
│   │   ├── llx_flutter_method_channel.dart
│   │   └── src/
│   │       └── models.dart         # 数据模型
│   ├── android/                    # Android 平台
│   │   ├── src/main/kotlin/com/inferx/llx_flutter/
│   │   │   └── LlxFlutterPlugin.kt # 平台实现
│   │   ├── build.gradle            # 构建配置
│   │   └── settings.gradle         # 包含 llx-android
│   ├── pubspec.yaml                # 插件配置
│   ├── README.md                   # 插件文档
│   ├── CHANGELOG.md                # 变更日志
│   └── example/                    # 样例应用
│       ├── lib/
│       │   └── main.dart           # 样例代码
│       ├── android/
│       │   └── settings.gradle.kts # 包含 llx-android
│       ├── pubspec.yaml            # 依赖配置
│       └── README.md               # 样例文档
├── README.md                       # Flutter 总览
└── BUILD.md                        # 本文件
```

## 调试

### Dart 代码调试

在 VS Code 或 Android Studio 中设置断点，然后以调试模式运行：

```bash
flutter run --debug
```

### Android 原生代码调试

1. 在 Android Studio 中打开 `flutter/llx_flutter/example/android`
2. 在 `LlxFlutterPlugin.kt` 中设置断点
3. 选择 "Debug 'app'" 启动调试

### 查看日志

```bash
# Flutter 日志
flutter logs

# Android 日志（包括原生）
adb logcat | grep -E "flutter|LLX|llx"
```

## 性能优化

### Release 构建

```bash
cd flutter/llx_flutter/example
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

### 优化建议

1. **使用量化模型**: 优先使用 Q4_K_M 或 Q5_K_M 量化
2. **调整上下文长度**: 根据设备内存调整 nCtx（默认 8192）
3. **线程数**: 让系统自动探测（nThreads = 0）

## 常见问题

### Q: 编译时找不到 llx-android

**解决方案**:
1. 确保 `settings.gradle` 中正确包含了 llx-android
2. 检查相对路径是否正确
3. 重新构建 llx-android 模块

### Q: 运行时提示找不到 libllx-android.so

**解决方案**:
1. 清理并重新构建：
   ```bash
   cd android/llx-android
   ./gradlew clean assembleRelease
   ```
2. 确保设备架构是 arm64-v8a

### Q: 模型加载失败

**解决方案**:
1. 检查文件格式是否为 `.gguf`
2. 确保文件完整（未损坏）
3. 检查设备内存是否充足
4. 查看错误日志：`await llx.lastError()`

### Q: Flutter 版本不兼容

**解决方案**:
```bash
flutter upgrade
flutter clean
flutter pub get
```

### Q: Gradle 构建缓慢

**解决方案**:
1. 启用 Gradle 并行构建（`gradle.properties`）:
   ```properties
   org.gradle.parallel=true
   org.gradle.caching=true
   ```
2. 使用国内镜像源

## 测试

### 单元测试

```bash
cd flutter/llx_flutter
flutter test
```

### 集成测试

```bash
cd flutter/llx_flutter/example
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/plugin_integration_test.dart
```

## 发布

### 1. 更新版本号

在 `pubspec.yaml` 中更新版本：

```yaml
version: 0.0.2
```

### 2. 更新 CHANGELOG

在 `CHANGELOG.md` 中记录变更。

### 3. 构建产物

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# App Bundle (用于 Google Play)
flutter build appbundle --release
```

### 4. 测试

在多个设备上测试构建产物。

## 贡献

### 代码风格

- 遵循 Flutter 和 Dart 风格指南
- 使用 `flutter format` 格式化代码
- 使用 `flutter analyze` 检查代码

### 提交流程

1. Fork 项目
2. 创建功能分支：`git checkout -b feature/xxx`
3. 提交代码：`git commit -m "Add xxx feature"`
4. 推送分支：`git push origin feature/xxx`
5. 创建 Pull Request

## 资源

- [Flutter 官方文档](https://flutter.dev/docs)
- [Platform Channels](https://docs.flutter.dev/platform-integration/platform-channels)
- [Android Plugin 开发](https://docs.flutter.dev/packages-and-plugins/developing-packages)
- [llama.cpp](https://github.com/ggerganov/llama.cpp)

## 支持

如遇问题，请：

1. 查看 [FAQ](../README.md#常见问题)
2. 搜索 [Issues](https://github.com/yourusername/inferx-sdk/issues)
3. 创建新 Issue（提供详细信息和日志）

## 许可证

与 inferx-sdk 项目保持一致。

