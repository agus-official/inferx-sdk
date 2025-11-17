import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llx_flutter/llx_flutter.dart';

import 'chat_backend.dart';

/// 全局聊天控制器：集中管理模型、会话、消息与 LoRA 状态
class ChatController {
  ChatController({ChatBackend? backend})
    : _backend = backend ?? LocalChatBackend();

  static final ChatController instance = ChatController();

  final ChatBackend _backend;

  // 基本状态
  final ValueNotifier<bool> isLoadingModel = ValueNotifier(false);
  final ValueNotifier<bool> isModelLoaded = ValueNotifier(false);
  final ValueNotifier<bool> isGenerating = ValueNotifier(false);

  // 数据状态
  final ValueNotifier<List<ChatMessage>> messages =
      ValueNotifier<List<ChatMessage>>(<ChatMessage>[]);
  final ValueNotifier<List<LoraItem>> loras = ValueNotifier<List<LoraItem>>(
    <LoraItem>[],
  );
  final ValueNotifier<List<String>> debugLogs = ValueNotifier<List<String>>(
    <String>[],
  );

  String? currentModelPath;
  Stream<ChatStreamEvent>? generationStream;

  final List<Map<String, String>> _chatHistory = <Map<String, String>>[];

  // 后端状态快照
  bool get isReady => _backend.isReady;

  // 生命周期
  Future<void> init() async {
    await _backend.initBackend();
  }

  Future<void> dispose() async {
    await _backend.freeBackend();
  }

  // 日志
  void log(String content) {
    final List<String> next = List<String>.from(debugLogs.value);
    next.add('[${DateTime.now().toIso8601String()}] $content');
    debugLogs.value = next;
  }

  // 模型
  Future<bool> prepareModel(String modelPath) async {
    if (isGenerating.value) return false;
    if (isModelLoaded.value) return true;

    isLoadingModel.value = true;
    try {
      final bool ok = await _backend.prepareModel(modelPath);
      if (!ok) {
        final err = await _backend.lastError();
        throw StateError('模型/会话准备失败：$err');
      }
      isModelLoaded.value = true;
      currentModelPath = modelPath;
      log('模型加载成功: $modelPath');
      return true;
    } catch (e) {
      log('加载模型失败: $e');
      rethrow;
    } finally {
      isLoadingModel.value = false;
    }
  }

  Future<void> unloadModel() async {
    if (!isModelLoaded.value) return;
    await _backend.unloadModel();
    isModelLoaded.value = false;
    currentModelPath = null;
    loras.value = <LoraItem>[];
    log('已卸载模型');
  }

  // LoRA
  Future<void> clearAllLora() async {
    if (!_backend.isReady) return;
    await _backend.clearLora();
    loras.value = <LoraItem>[];
    log('已清空所有 LoRA');
  }

  Future<bool> addOrUpdateLora(String path, double scale) async {
    if (!_backend.isReady) return false;
    final int existing = loras.value.indexWhere((e) => e.path == path);
    bool success;
    if (existing >= 0) {
      success = await _backend.updateLoraScale(path, scale);
      if (success) {
        final List<LoraItem> next = List<LoraItem>.from(loras.value);
        next[existing] = next[existing].copyWith(scale: scale);
        loras.value = next;
        log('更新 LoRA scale: $path -> $scale');
      }
    } else {
      success = await _backend.addLora(path, scale: scale);
      if (success) {
        final List<LoraItem> next = List<LoraItem>.from(loras.value)
          ..add(LoraItem(path: path, scale: scale));
        loras.value = next;
        log('加载 LoRA: $path (scale=$scale)');
      }
    }
    if (!success) {
      final err = await _backend.lastError();
      log('LoRA 操作失败: $err');
    }
    return success;
  }

  Future<void> removeLora(String path) async {
    if (!_backend.isReady) return;
    await _backend.removeLora(path);
    final List<LoraItem> next = List<LoraItem>.from(loras.value)
      ..removeWhere((e) => e.path == path);
    loras.value = next;
    log('移除 LoRA: $path');
  }

  // 生成
  Future<void> sendUserMessage(String content) async {
    if (content.trim().isEmpty || !isModelLoaded.value || isGenerating.value)
      return;

    // 加入历史
    _chatHistory.add(<String, String>{'role': 'user', 'content': content});

    // 更新消息列表：用户 + 占位助手
    final List<ChatMessage> next = List<ChatMessage>.from(messages.value)
      ..add(ChatMessage(role: 'user', content: content))
      ..add(const ChatMessage(role: 'assistant', content: ''));
    messages.value = next;

    // 开始生成
    isGenerating.value = true;
    final List<ChatMessage> history = _chatHistory
        .map(
          (e) => ChatMessage(
            role: e['role'] ?? 'user',
            content: e['content'] ?? '',
          ),
        )
        .toList(growable: false);

    final Stream<ChatStreamEvent> stream = _backend
        .generateFromMessages(history)
        .asBroadcastStream();
    generationStream = stream;

    // 结束时提交最终答案并复位
    stream.listen(
      (ChatStreamEvent event) {
        if (event.finished) {
          // 消息列表只在结束时更新（把最后一条 assistant 替换成最终内容）
          final List<ChatMessage> cur = List<ChatMessage>.from(messages.value);
          if (cur.isNotEmpty && cur.last.role == 'assistant') {
            cur[cur.length - 1] = ChatMessage(
              role: 'assistant',
              content: event.content,
            );
            messages.value = cur;
          }
          _chatHistory.add(<String, String>{
            'role': 'assistant',
            'content': event.content,
          });
          isGenerating.value = false;
          generationStream = null;
        }
      },
      onError: (Object e) {
        log('生成失败：$e');
        isGenerating.value = false;
        generationStream = null;
      },
    );
  }

  // 工具
  Future<String> systemInfo() => _backend.systemInfo();

  Future<String> bench({int pp = 8, int tg = 4, int pl = 1, int nr = 1}) async {
    if (!_backend.isReady) return '后端未准备好';
    return _backend.bench(pp: pp, tg: tg, pl: pl, nr: nr);
  }

  Future<String> lastError() => _backend.lastError();
}
