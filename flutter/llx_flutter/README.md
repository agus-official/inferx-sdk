# llx_flutter

Flutter plugin for inferx-sdk，提供基于 llama.cpp 的 LLM 能力。

## 功能特性

- ✅ 加载和管理 GGUF 模型
- ✅ 流式文本生成
- ✅ 多 LoRA 适配器支持
- ✅ OpenAI 兼容的 chat completion API
- ✅ 基准测试工具
- ✅ 聊天历史管理
- ⏳ iOS 支持（待实现）

## 平台支持

| Android | iOS |
|---------|-----|
| ✅      | ⏳  |

- **Android**: 完全支持，依赖 `llx-android` 原生模块
- **iOS**: 暂未实现

## 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  llx_flutter:
    path: ../path/to/flutter/llx_flutter
```

## Android 配置

### 1. 确保 llx-android 模块已构建

```bash
cd android/llx-android
./gradlew assembleRelease
```

### 2. 在你的 Flutter 项目中配置

在 `android/settings.gradle.kts` 中包含 llx-android 模块：

```kotlin
include(':llx-android')
project(':llx-android').projectDir = File('../../android/llx-android')
```

## 基本用法

### 初始化和加载模型

```dart
import 'package:llx_flutter/llx_flutter.dart';

final llx = LlxFlutter();

// 初始化后端
await llx.initBackend();

// 加载模型
final modelHandle = await llx.modelLoad('/path/to/model.gguf');

// 创建会话
final sessionHandle = await llx.sessionCreate(
  modelHandle,
  nCtx: 8192,
  nThreads: 0, // 0 表示自动探测
);
```

### 流式生成

```dart
// 从消息 JSON 初始化
final messagesJson = '[{"role":"user","content":"你好"}]';
await llx.sessionInitFromMessagesJson(sessionHandle, messagesJson);

// 逐步生成
while (true) {
  final result = await llx.sessionStep(sessionHandle);
  print(result.text);
  if (result.finished) break;
}
```

### LoRA 管理

```dart
// 添加 LoRA
await llx.sessionAddLora(sessionHandle, '/path/to/lora.gguf', scale: 1.0);

// 更新 LoRA scale
await llx.sessionUpdateLoraScale(sessionHandle, '/path/to/lora.gguf', 1.5);

// 移除 LoRA
await llx.sessionRemoveLora(sessionHandle, '/path/to/lora.gguf');

// 清空所有 LoRA
await llx.sessionClearLora(sessionHandle);
```

### OpenAI 兼容 API

```dart
final requestJson = '''
{
  "model": "local-llm",
  "messages": [
    {"role": "user", "content": "你好"}
  ],
  "temperature": 0.7,
  "max_tokens": 1024
}
''';

final responseJson = await llx.chatCompleteJson(sessionHandle, requestJson);
print(responseJson);
```

### 清理资源

```dart
// 清空 KV 缓存
await llx.sessionKvClear(sessionHandle);

// 释放会话
await llx.sessionFree(sessionHandle);

// 释放模型
await llx.modelFree(modelHandle);

// 释放后端
await llx.freeBackend();
```

## API 文档

### 主要方法

#### 后端管理

- `initBackend()`: 初始化后端
- `freeBackend()`: 释放后端
- `systemInfo()`: 获取系统信息

#### 模型管理

- `modelLoad(String path)`: 加载模型，返回模型句柄
- `modelFree(int modelHandle)`: 释放模型

#### 会话管理

- `sessionCreate(int modelHandle, {int nCtx, int nThreads})`: 创建会话
- `sessionFree(int sessionHandle)`: 释放会话
- `sessionKvClear(int sessionHandle)`: 清空 KV 缓存

#### 文本生成

- `sessionInitFromText(int sessionHandle, String text, {bool formatChat, int nLen})`: 从文本初始化
- `sessionInitFromMessagesJson(int sessionHandle, String messagesJson, {int nLen})`: 从消息 JSON 初始化
- `sessionStep(int sessionHandle, {int nLen})`: 单步生成
- `chatCompleteJson(int sessionHandle, String requestJson)`: OpenAI 兼容的 chat completion

#### LoRA 管理

- `sessionLoadLora(int sessionHandle, String loraPath, {double scale})`: 加载单个 LoRA（清空已有）
- `sessionAddLora(int sessionHandle, String loraPath, {double scale})`: 添加 LoRA（保留已有）
- `sessionUpdateLoraScale(int sessionHandle, String loraPath, double scale)`: 更新 scale
- `sessionRemoveLora(int sessionHandle, String loraPath)`: 移除指定 LoRA
- `sessionClearLora(int sessionHandle)`: 清空所有 LoRA

#### 工具方法

- `bench(int sessionHandle, {int pp, int tg, int pl, int nr})`: 运行基准测试
- `lastError()`: 获取最后错误信息

## 样例应用

查看 `example` 目录下的完整样例应用，包含：

- 🗨️ 聊天界面
- 📁 模型文件选择和加载
- 🔧 LoRA 管理（添加、调整 scale、移除）
- 📊 基准测试
- 📋 聊天历史管理

### 运行样例

```bash
cd flutter/llx_flutter/example
flutter pub get
flutter run
```

## 注意事项

1. **模型文件**: 确保模型文件格式为 `.gguf`，并且应用有读取权限
2. **内存占用**: 大模型会占用大量内存，建议在测试前检查设备可用内存
3. **ABI 支持**: Android 目前仅支持 `arm64-v8a`
4. **权限**: Android 需要存储权限来读取模型文件

## 架构

```
Flutter App
    ↓
llx_flutter (Dart)
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

## 许可证

与 inferx-sdk 保持一致。

## 相关链接

- [inferx-sdk](../../README.md)
- [llx-android](../../android/llx-android/README.md)
- [llama.cpp](https://github.com/ggerganov/llama.cpp)
