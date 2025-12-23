import 'dart:async';
import 'dart:convert';

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

  /// 基于 OpenAI messages 结构开始一次生成（可包含 tool_calls/tool 响应等字段）
  /// - messages: List<Map>，元素形如 {"role":"user","content":"..."} 或 tool message 等
  Stream<ChatStreamEvent> generateFromOaiMessages(
    List<Map<String, dynamic>> messages, {
    required ChatRequestOptions options,
  });

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

/// Chat/completions 请求选项（示例侧使用）
class ChatRequestOptions {
  final String modelName; // request_json 里的 "model"
  final bool enableTools;
  final String toolFormat; // auto|openai|functiongemma
  final int maxToolCalls; // 0=unlimited
  final int maxTokens;
  final double temperature;
  final double topP;
  final int topK;
  final bool parseToolCalls;

  const ChatRequestOptions({
    this.modelName = 'local-llm',
    this.enableTools = false,
    this.toolFormat = 'auto',
    this.maxToolCalls = 0,
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.parseToolCalls = true,
  });
}

/// 本地后端：封装 LlxFlutter，并以固定频率聚合发出内容，降低刷新
class LocalChatBackend implements ChatBackend {
  final LlxFlutter _llx;
  final Duration emitInterval;
  void Function(String msg)? onLog;
  void Function(ChatMessage msg)? onUiMessage;

  int _modelHandle = 0;
  int _sessionHandle = 0;
  String? _modelPath;

  LocalChatBackend({
    LlxFlutter? llx,
    this.emitInterval = const Duration(milliseconds: 10),
    this.onLog,
    this.onUiMessage,
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
  Stream<ChatStreamEvent> generateFromOaiMessages(
    List<Map<String, dynamic>> messages, {
    required ChatRequestOptions options,
  }) async* {
    if (!isReady) throw StateError('Backend not ready');

    // 如果启用工具，使用 OpenAI chatCompleteJson（支持 tools/tool_calls/stop/tool_format 等）
    if (options.enableTools) {
      yield* _generateViaChatCompletion(messages, options);
      return;
    }

    // 否则保留旧的 sessionStep 流式路径（不带 tools）
    yield* _generateViaSessionStep(messages);
  }

  Stream<ChatStreamEvent> _generateViaSessionStep(
    List<Map<String, dynamic>> messages,
  ) async* {
    // 仅支持 {role, content} 的最简 messages
    final minimal = messages
        .where((m) => m['role'] is String)
        .map(
          (m) => ChatMessage(
            role: m['role'] as String,
            content: (m['content'] ?? '').toString(),
          ),
        )
        .toList(growable: false);

    final messagesJson = jsonEncode(minimal.map((m) => m.toJson()).toList());
    await _llx.sessionInitFromMessagesJson(_sessionHandle, messagesJson);

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
      if (!controller.isClosed && buffer.isNotEmpty && !finished) emitNow();
    });

    () async {
      try {
        while (true) {
          final step = await _llx.sessionStep(_sessionHandle);
          if (step.text.isNotEmpty) buffer.write(step.text);
          if (step.finished) break;
        }
        finished = true;
        ticker?.cancel();
        controller.add(
          ChatStreamEvent(content: buffer.toString(), finished: true),
        );
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

  Stream<ChatStreamEvent> _generateViaChatCompletion(
    List<Map<String, dynamic>> messages,
    ChatRequestOptions options,
  ) async* {
    final controller = StreamController<ChatStreamEvent>();

    () async {
      try {
        final tools = _defaultToolsSchema();
        final toolHandlers = _defaultToolHandlers();

        // 执行 tool loop：直到模型不再返回 tool_calls
        for (int iter = 0; iter < 8; iter++) {
          // 为了避免 KV 残留影响（我们的 chatComplete 走“每次完整 prefill”），每轮清空 KV
          await _llx.sessionKvClear(_sessionHandle);

          final req = <String, dynamic>{
            'model': options.modelName,
            'messages': messages,
            'temperature': options.temperature,
            'top_p': options.topP,
            'top_k': options.topK,
            'max_tokens': options.maxTokens,
            'parse_tool_calls': options.parseToolCalls,
            'tool_format': options.toolFormat,
            'max_tool_calls': options.maxToolCalls,
          };

          if (tools.isNotEmpty) {
            req['tools'] = tools;
            req['tool_choice'] = 'auto';
            req['parallel_tool_calls'] = false;
          }

          // Ollama-compatible FunctionGemma stop sequences
          if (options.toolFormat == 'functiongemma') {
            if (options.maxToolCalls == 1) {
              req['stop'] = [
                '<end_function_call>',
                '<start_function_response>',
              ];
            } else {
              req['stop'] = ['<start_function_response>'];
            }
          }

          final respStr = await _llx.chatCompleteJson(
            _sessionHandle,
            jsonEncode(req),
          );

          final resp = jsonDecode(respStr) as Map<String, dynamic>;
          final choices = resp['choices'] as List<dynamic>? ?? const [];
          final msg =
              (choices.isNotEmpty ? (choices[0] as Map)['message'] : null)
                  as Map<String, dynamic>?;
          if (msg == null) {
            messages.add({'role': 'assistant', 'content': ''});
            controller.add(const ChatStreamEvent(content: '', finished: true));
            break;
          }

          final toolCalls = msg['tool_calls'];
          if (toolCalls is List && toolCalls.isNotEmpty) {
            // 追加 assistant tool_calls 消息
            messages.add(msg);

            for (final tc in toolCalls) {
              if (tc is! Map) continue;
              final id = (tc['id'] ?? 'call_0').toString();
              final fn = (tc['function'] is Map)
                  ? (tc['function'] as Map)
                  : const <String, dynamic>{};
              final name = (fn['name'] ?? '').toString();
              final argsRaw = fn['arguments'];
              String argsStr = '';
              if (argsRaw is String) {
                argsStr = argsRaw;
              } else if (argsRaw != null) {
                argsStr = jsonEncode(argsRaw);
              }

              onLog?.call('tool_call: $name($argsStr)');
              onUiMessage?.call(
                ChatMessage(role: 'tool_call', content: '$name($argsStr)'),
              );

              Map<String, dynamic> args = <String, dynamic>{};
              try {
                final parsed = jsonDecode(argsStr);
                if (parsed is Map<String, dynamic>) args = parsed;
              } catch (_) {
                // ignore
              }

              final handler = toolHandlers[name];
              final toolResult = (handler != null)
                  ? await handler(args)
                  : jsonEncode({'error': 'unknown tool'});

              onLog?.call('tool_result[$name]: $toolResult');
              onUiMessage?.call(
                ChatMessage(
                  role: 'tool_result',
                  content: '$name -> $toolResult',
                ),
              );

              // FunctionGemma template requires tool response name
              messages.add({
                'role': 'tool',
                'name': name,
                'tool_call_id': id,
                'content': toolResult,
              });
            }
            // 继续下一轮，让模型基于 tool 结果输出最终回答
            continue;
          }

          final content = msg['content'];
          final text = (content == null) ? '' : content.toString();
          messages.add(msg);
          controller.add(ChatStreamEvent(content: text, finished: true));
          break;
        }
      } catch (e) {
        controller.addError(e);
      } finally {
        await controller.close();
      }
    }();

    yield* controller.stream;
  }

  List<Map<String, dynamic>> _defaultToolsSchema() {
    return <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': 'get_weather',
          'description': 'Get the current weather for a city',
          'parameters': {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
            'required': ['city'],
          },
        },
      },
    ];
  }

  Map<String, Future<String> Function(Map<String, dynamic>)>
  _defaultToolHandlers() {
    return <String, Future<String> Function(Map<String, dynamic>)>{
      'get_weather': (Map<String, dynamic> args) async {
        final city = (args['city'] ?? '').toString();
        return jsonEncode({
          'city': city,
          'temperature': 22,
          'unit': 'celsius',
          'condition': 'sunny',
        });
      },
    };
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
  Stream<ChatStreamEvent> generateFromOaiMessages(
    List<Map<String, dynamic>> messages, {
    required ChatRequestOptions options,
  }) async* {
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
