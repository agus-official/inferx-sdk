library llx_flutter;

import 'llx_flutter_platform_interface.dart';

export 'src/models.dart';

/// Flutter plugin for inferx-sdk LLM capabilities
class LlxFlutter {
  /// 初始化后端
  Future<void> initBackend() {
    return LlxFlutterPlatform.instance.initBackend();
  }

  /// 释放后端
  Future<void> freeBackend() {
    return LlxFlutterPlatform.instance.freeBackend();
  }

  /// 加载模型
  /// 返回模型句柄
  Future<int> modelLoad(String path) {
    return LlxFlutterPlatform.instance.modelLoad(path);
  }

  /// 释放模型
  Future<void> modelFree(int modelHandle) {
    return LlxFlutterPlatform.instance.modelFree(modelHandle);
  }

  /// 创建会话
  /// [modelHandle] 模型句柄
  /// [nCtx] 上下文长度，默认 8192
  /// [nThreads] 线程数，<=0 自动探测
  /// 返回会话句柄
  Future<int> sessionCreate(
    int modelHandle, {
    int nCtx = 8192,
    int nThreads = 0,
  }) {
    return LlxFlutterPlatform.instance.sessionCreate(
      modelHandle,
      nCtx,
      nThreads,
    );
  }

  /// 释放会话
  Future<void> sessionFree(int sessionHandle) {
    return LlxFlutterPlatform.instance.sessionFree(sessionHandle);
  }

  /// 从文本初始化会话
  /// [formatChat] 是否格式化为聊天模板
  /// [nLen] 最大生成长度
  /// 返回 prefill token 数量
  Future<int> sessionInitFromText(
    int sessionHandle,
    String text, {
    bool formatChat = true,
    int nLen = 1024,
  }) {
    return LlxFlutterPlatform.instance.sessionInitFromText(
      sessionHandle,
      text,
      formatChat,
      nLen,
    );
  }

  /// 从消息 JSON 初始化会话
  /// [messagesJson] OpenAI 兼容的消息 JSON 数组字符串
  /// [nLen] 最大生成长度
  /// 返回 prefill token 数量
  Future<int> sessionInitFromMessagesJson(
    int sessionHandle,
    String messagesJson, {
    int nLen = 1024,
  }) {
    return LlxFlutterPlatform.instance.sessionInitFromMessagesJson(
      sessionHandle,
      messagesJson,
      nLen,
    );
  }

  /// 清空会话 KV 缓存
  Future<void> sessionKvClear(int sessionHandle) {
    return LlxFlutterPlatform.instance.sessionKvClear(sessionHandle);
  }

  /// 单步生成
  /// [nLen] 最大生成长度
  /// 返回 StepResult，包含生成的文本片段和是否结束标志
  Future<StepResult> sessionStep(int sessionHandle, {int nLen = 1024}) {
    return LlxFlutterPlatform.instance.sessionStep(sessionHandle, nLen);
  }

  /// OpenAI 兼容的 chat completion API
  /// [requestJson] OpenAI 格式的请求 JSON
  /// 返回 OpenAI 格式的响应 JSON
  Future<String> chatCompleteJson(int sessionHandle, String requestJson) {
    return LlxFlutterPlatform.instance.chatCompleteJson(
      sessionHandle,
      requestJson,
    );
  }

  /// 获取系统信息
  Future<String> systemInfo() {
    return LlxFlutterPlatform.instance.systemInfo();
  }

  /// 基准测试
  /// [pp] prompt processing 的 token 数
  /// [tg] text generation 的步数
  /// [pl] 并行序列数
  /// [nr] 重复次数
  /// 返回 Markdown 格式的测试结果
  Future<String> bench(
    int sessionHandle, {
    int pp = 8,
    int tg = 4,
    int pl = 1,
    int nr = 1,
  }) {
    return LlxFlutterPlatform.instance.bench(sessionHandle, pp, tg, pl, nr);
  }

  // LoRA 相关方法

  /// 加载单个 LoRA（会清空已有的 LoRA）
  Future<bool> sessionLoadLora(
    int sessionHandle,
    String loraPath, {
    double scale = 1.0,
  }) {
    return LlxFlutterPlatform.instance.sessionLoadLora(
      sessionHandle,
      loraPath,
      scale,
    );
  }

  /// 添加 LoRA（不清空已有的 LoRA）
  Future<bool> sessionAddLora(
    int sessionHandle,
    String loraPath, {
    double scale = 1.0,
  }) {
    return LlxFlutterPlatform.instance.sessionAddLora(
      sessionHandle,
      loraPath,
      scale,
    );
  }

  /// 更新 LoRA 的 scale
  Future<bool> sessionUpdateLoraScale(
    int sessionHandle,
    String loraPath,
    double scale,
  ) {
    return LlxFlutterPlatform.instance.sessionUpdateLoraScale(
      sessionHandle,
      loraPath,
      scale,
    );
  }

  /// 移除指定 LoRA
  Future<void> sessionRemoveLora(int sessionHandle, String loraPath) {
    return LlxFlutterPlatform.instance.sessionRemoveLora(
      sessionHandle,
      loraPath,
    );
  }

  /// 清空所有 LoRA
  Future<void> sessionClearLora(int sessionHandle) {
    return LlxFlutterPlatform.instance.sessionClearLora(sessionHandle);
  }

  /// 获取最后一次错误信息
  Future<String> lastError() {
    return LlxFlutterPlatform.instance.lastError();
  }
}

/// 单步生成结果
class StepResult {
  /// 生成的文本片段
  final String text;

  /// 是否已结束生成
  final bool finished;

  const StepResult({required this.text, required this.finished});

  factory StepResult.fromMap(Map<dynamic, dynamic> map) {
    return StepResult(
      text: map['text'] as String? ?? '',
      finished: map['finished'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {'text': text, 'finished': finished};
  }

  @override
  String toString() => 'StepResult(text: $text, finished: $finished)';
}
