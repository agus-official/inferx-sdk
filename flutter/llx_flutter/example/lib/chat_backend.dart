import 'dart:async';

import 'package:llx_flutter/llx_flutter.dart';

/// 聊天流事件：携带当前完整内容与是否结束
class ChatStreamEvent {
  final String content; // 累积后的完整内容
  final bool finished; // 是否结束

  const ChatStreamEvent({required this.content, required this.finished});
}

/// 统一聊天后端接口（本地/远程均实现该接口）
abstract class ChatBackend {
  Future<void> initBackend();
  Future<void> freeBackend();

  /// 加载并准备模型与会话；远程后端可忽略
  Future<bool> prepareModel(String modelPath);

  /// 卸载模型/销毁会话
  Future<void> unloadModel();

  /// 是否已准备好（本地：模型+会话）
  bool get isReady;

  /// 当前模型路径（本地）
  String? get currentModelPath;

  /// 基于历史消息开始一次流式生成，返回按节流频率聚合后的完整内容流
  Stream<ChatStreamEvent> generateFromMessages(List<ChatMessage> history);

  /// LoRA 操作（远程后端可为 no-op）
  Future<bool> addLora(String path, {double scale = 1.0});
  Future<bool> updateLoraScale(String path, double scale);
  Future<void> removeLora(String path);
  Future<void> clearLora();

  /// 信息与工具
  Future<String> systemInfo();
  Future<String> bench({int pp = 8, int tg = 4, int pl = 1, int nr = 1});
  Future<String> lastError();
}

/// 本地后端：封装 LlxFlutter，并以固定频率聚合发出内容，降低刷新
class LocalChatBackend implements ChatBackend {
  final LlxFlutter _llx;
  final Duration emitInterval;

  int _modelHandle = 0;
  int _sessionHandle = 0;
  String? _modelPath;

  LocalChatBackend({
    LlxFlutter? llx,
    this.emitInterval = const Duration(milliseconds: 10),
  }) : _llx = llx ?? LlxFlutter();

  @override
  Future<void> initBackend() => _llx.initBackend();

  @override
  Future<void> freeBackend() async {
    await unloadModel();
    await _llx.freeBackend();
  }

  @override
  Future<bool> prepareModel(String modelPath) async {
    if (_modelHandle != 0) return true;
    _modelHandle = await _llx.modelLoad(modelPath);
    if (_modelHandle == 0) return false;

    _sessionHandle = await _llx.sessionCreate(_modelHandle);
    if (_sessionHandle == 0) return false;

    _modelPath = modelPath;
    return true;
  }

  @override
  Future<void> unloadModel() async {
    if (_sessionHandle != 0) {
      await _llx.sessionFree(_sessionHandle);
      _sessionHandle = 0;
    }
    if (_modelHandle != 0) {
      await _llx.modelFree(_modelHandle);
      _modelHandle = 0;
    }
    _modelPath = null;
  }

  @override
  bool get isReady => _sessionHandle != 0 && _modelHandle != 0;

  @override
  String? get currentModelPath => _modelPath;

  @override
  Stream<ChatStreamEvent> generateFromMessages(
    List<ChatMessage> history,
  ) async* {
    if (!isReady) throw StateError('Backend not ready');

    // 构建 OpenAI 兼容 JSON
    final messagesJson = history
        .map(
          (m) =>
              '{"role":"${_escape(m.role)}","content":"${_escape(m.content)}"}',
        )
        .join(',');
    final fullJson = '[$messagesJson]';

    await _llx.sessionInitFromMessagesJson(_sessionHandle, fullJson);

    // 聚合输出：按 emitInterval 频率发出完整内容，避免 UI 过于频繁重建
    final controller = StreamController<ChatStreamEvent>();
    final buffer = StringBuffer();
    Timer? ticker;
    bool finished = false;

    void emitNow() {
      controller.add(
        ChatStreamEvent(content: buffer.toString(), finished: false),
      );
    }

    ticker = Timer.periodic(emitInterval, (_) {
      if (!controller.isClosed && buffer.isNotEmpty && !finished) {
        emitNow();
      }
    });

    () async {
      try {
        while (true) {
          final step = await _llx.sessionStep(_sessionHandle);
          if (step.text.isNotEmpty) {
            buffer.write(step.text);
          }
          if (step.finished) break;
        }
        finished = true;
        ticker?.cancel();
        // 发送最终完整内容与结束标志
        controller.add(
          ChatStreamEvent(content: buffer.toString(), finished: true),
        );
        // 清空 KV，准备下次对话
        await _llx.sessionKvClear(_sessionHandle);
      } catch (e) {
        ticker?.cancel();
        controller.addError(e);
      } finally {
        await controller.close();
      }
    }();

    yield* controller.stream;
  }

  @override
  Future<bool> addLora(String path, {double scale = 1.0}) async {
    if (!isReady) return false;
    return _llx.sessionAddLora(_sessionHandle, path, scale: scale);
  }

  @override
  Future<bool> updateLoraScale(String path, double scale) async {
    if (!isReady) return false;
    return _llx.sessionUpdateLoraScale(_sessionHandle, path, scale);
  }

  @override
  Future<void> removeLora(String path) async {
    if (!isReady) return;
    await _llx.sessionRemoveLora(_sessionHandle, path);
  }

  @override
  Future<void> clearLora() async {
    if (!isReady) return;
    await _llx.sessionClearLora(_sessionHandle);
  }

  @override
  Future<String> systemInfo() => _llx.systemInfo();

  @override
  Future<String> bench({int pp = 8, int tg = 4, int pl = 1, int nr = 1}) async {
    if (!isReady) return '后端未准备好';
    return _llx.bench(_sessionHandle, pp: pp, tg: tg, pl: pl, nr: nr);
  }

  @override
  Future<String> lastError() => _llx.lastError();

  String _escape(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}

/// 远程后端占位实现（SSE/WebSocket 可在此实现）
class RemoteChatBackend implements ChatBackend {
  final Uri baseUri;
  final Duration emitInterval;

  RemoteChatBackend({
    required this.baseUri,
    this.emitInterval = const Duration(milliseconds: 300),
  });

  @override
  Future<void> freeBackend() async {}

  @override
  Future<void> initBackend() async {}

  @override
  bool get isReady => true; // 远程后端通常无需本地准备

  @override
  String? get currentModelPath => null;

  @override
  Future<bool> prepareModel(String modelPath) async => true; // 远程忽略

  @override
  Future<void> unloadModel() async {}

  @override
  Stream<ChatStreamEvent> generateFromMessages(
    List<ChatMessage> history,
  ) async* {
    // 这里可实现 SSE/WebSocket，并按 emitInterval 聚合；先返回错误占位
    yield const ChatStreamEvent(
      content: 'Remote backend 未实现流式连接',
      finished: true,
    );
  }

  @override
  Future<bool> addLora(String path, {double scale = 1.0}) async => true;

  @override
  Future<void> clearLora() async {}

  @override
  Future<String> lastError() async => '';

  @override
  Future<String> systemInfo() async => 'Remote backend: ${baseUri.toString()}';

  @override
  Future<void> removeLora(String path) async {}

  @override
  Future<bool> updateLoraScale(String path, double scale) async => true;

  @override
  Future<String> bench({
    int pp = 8,
    int tg = 4,
    int pl = 1,
    int nr = 1,
  }) async => 'N/A for remote backend';
}
