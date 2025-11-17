import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../chat_backend.dart';
import '../../chat_controller.dart';
import '../../widgets/lora_sheet.dart';
import 'widgets/message_list.dart';
import 'widgets/message_input.dart';
import 'widgets/app_bar_title.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatController _controller = ChatController.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _autoScroll = true;
  bool _userTouchedScroll = false;
  bool _isAtBottom = true;
  final double _bottomTolerance = 24.0;
  bool _pendingAutoScroll = false;

  Stream<ChatStreamEvent>? _generationStream;
  StreamSubscription<ChatStreamEvent>? _genSub;

  @override
  void initState() {
    super.initState();
    _initBackend();
  }

  Future<void> _initBackend() async {
    try {
      await _controller.init();
      final String info = await _controller.systemInfo();
      _controller.log('系统信息：\n$info');
    } catch (e) {
      _controller.log('初始化失败：$e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _genSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final String text = _messageController.text.trim();
    if (text.isEmpty ||
        !_controller.isModelLoaded.value ||
        _controller.isGenerating.value)
      return;

    _messageController.clear();
    FocusScope.of(context).unfocus();
    _autoScroll = true;
    _userTouchedScroll = false;
    _isAtBottom = true;
    _scheduleAutoScrollToBottom(animated: false);

    try {
      // ignore: unawaited_futures
      _controller.sendUserMessage(text);
      _generationStream = _controller.generationStream;

      _genSub?.cancel();
      if (_generationStream != null) {
        _genSub = _generationStream!.listen((ChatStreamEvent event) {
          if (!event.finished && event.content.isNotEmpty) {
            _scheduleAutoScrollToBottom();
          }
          if (event.finished) {
            setState(() => _generationStream = null);
          }
        });
      }
    } catch (e) {
      _controller.log('生成失败：$e');
    }
  }

  void _openLoraSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (BuildContext context) => const LoraSheet(),
    );
  }

  void _openModelSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (BuildContext context) => const ModelSheet(),
    );
  }

  void _openDebugConsole() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (BuildContext context) => DebugConsole(onBench: _runBench),
    );
  }

  Future<void> _runBench() async {
    if (!_controller.isReady) return;
    try {
      _controller.log('正在运行基准测试...');
      final String result = await _controller.bench(pp: 8, tg: 4, pl: 1, nr: 1);
      _controller.log(result);
    } catch (e) {
      _controller.log('基准测试失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        centerTitle: true,
        title: AppBarTitle(onTap: _openModelSheet),
        leading: IconButton(
          onPressed: _openDebugConsole,
          icon: const Icon(Icons.terminal),
        ),
        actions: [
          ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[
              _controller.isModelLoaded,
              _controller.isGenerating,
            ]),
            builder: (BuildContext context, _) => IconButton(
              tooltip: 'LoRA 配置',
              icon: const Icon(Icons.tune),
              onPressed:
                  (_controller.isModelLoaded.value &&
                      !_controller.isGenerating.value)
                  ? _openLoraSheet
                  : null,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Listener(
              onPointerDown: (_) {
                _userTouchedScroll = true;
                _autoScroll = false; // 触摸立即退出自动吸附
              },
              onPointerUp: (_) {
                _userTouchedScroll = false;
                // 手指抬起后，仅当当前就在底部时才恢复自动吸附
                if (_isAtBottom) {
                  _autoScroll = true;
                  _scheduleAutoScrollToBottom();
                }
              },
              onPointerCancel: (_) {
                _userTouchedScroll = false;
                if (_isAtBottom) {
                  _autoScroll = true;
                  _scheduleAutoScrollToBottom();
                }
              },
              child: Stack(
                children: <Widget>[
                  NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification n) {
                      if (!_scrollController.hasClients) return false;
                      final ScrollPosition position =
                          _scrollController.position;
                      final bool isAtBottom =
                          position.extentAfter <= _bottomTolerance;
                      // 仅在没有手指触摸时，因为到达底部而开启自动吸附
                      if (isAtBottom && !_userTouchedScroll) {
                        _autoScroll = true;
                      } else if (_userTouchedScroll) {
                        _autoScroll = false;
                      }
                      if (isAtBottom != _isAtBottom) {
                        setState(() => _isAtBottom = isAtBottom);
                      }
                      return false;
                    },
                    child: MessageList(
                      controller: _scrollController,
                      generationStream: _generationStream,
                      isGenerating: _controller.isGenerating,
                      messagesListenable: _controller.messages,
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedOpacity(
                      opacity: (!_autoScroll && !_isAtBottom) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: IgnorePointer(
                        ignoring: (_autoScroll || _isAtBottom),
                        child: FloatingActionButton(
                          mini: true,
                          onPressed: () {
                            if (!_scrollController.hasClients) return;
                            _autoScroll = true;
                            _userTouchedScroll = false;
                            _scheduleAutoScrollToBottom();
                          },
                          child: const Icon(Icons.arrow_downward_rounded),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: MessageInput(
              controller: _messageController,
              canSendListenable: Listenable.merge(<Listenable>[
                _controller.isModelLoaded,
                _controller.isGenerating,
                _controller.isLoadingModel,
              ]),
              enabledBuilder: () {
                return _controller.isModelLoaded.value &&
                    !_controller.isGenerating.value &&
                    !_controller.isLoadingModel.value;
              },
              isGenerating: _controller.isGenerating,
              isLoadingModel: _controller.isLoadingModel,
              onSend: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  void _scheduleAutoScrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (!_autoScroll || _userTouchedScroll) return;
    if (_pendingAutoScroll) return;
    _pendingAutoScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_scrollController.hasClients) {
        _pendingAutoScroll = false;
        return;
      }
      final position = _scrollController.position;
      final double target = position.maxScrollExtent;
      final double delta = (target - position.pixels).abs();
      if (delta <= 1.0) {
        _pendingAutoScroll = false;
        return;
      }
      try {
        if (animated) {
          await _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(target);
        }
      } finally {
        _pendingAutoScroll = false;
      }
    });
  }
}

/// 以下为从旧结构分离出的局部 UI 组件（ModelSheet/DebugConsole）
class ModelSheet extends StatelessWidget {
  const ModelSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final ChatController c = ChatController.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.smart_toy_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: c.isModelLoaded,
                    builder: (BuildContext context, bool loaded, Widget? _) {
                      final String text = c.currentModelPath ?? '未加载模型';
                      return Text(text, overflow: TextOverflow.ellipsis);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: c.isLoadingModel,
                  builder: (BuildContext context, bool loading, Widget? _) {
                    return loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const SizedBox.shrink();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FilledButton.icon(
                  onPressed: c.isGenerating.value
                      ? null
                      : () => _pickAndLoadModel(context),
                  icon: const Icon(Icons.file_open),
                  label: const Text('选择并加载 GGUF'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: (!c.isModelLoaded.value || c.isGenerating.value)
                      ? null
                      : () async {
                          try {
                            await c.unloadModel();
                          } catch (e) {
                            c.log('卸载失败：$e');
                          }
                        },
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('卸载'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: c.isModelLoaded,
              builder: (BuildContext context, bool loaded, Widget? _) {
                if (!loaded || c.currentModelPath == null)
                  return const SizedBox.shrink();
                return Text(
                  '路径: ${c.currentModelPath!}',
                  style: const TextStyle(fontSize: 12),
                );
              },
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<bool>(
              valueListenable: c.isModelLoaded,
              builder: (BuildContext context, bool loaded, Widget? _) {
                if (!loaded) return const SizedBox.shrink();
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final String info = await c.systemInfo();
                          c.log('模型信息（系统）：\n$info');
                        } catch (e) {
                          c.log('查询信息失败：$e');
                        }
                      },
                      icon: const Icon(Icons.info_outline),
                      label: const Text('信息到 Console'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndLoadModel(BuildContext context) async {
    final ChatController c = ChatController.instance;
    if (c.isGenerating.value) return;
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;

      final PlatformFile file = result.files.first;
      if (file.path == null) return;

      if (!context.mounted) return;
      Navigator.of(context).pop();

      final Directory appDir = (Platform.isIOS || Platform.isMacOS)
          ? await getApplicationSupportDirectory()
          : (await getExternalStorageDirectory() ??
                await getApplicationDocumentsDirectory());
      final String fileName = file.name.endsWith('.gguf')
          ? file.name
          : '${file.name}.gguf';
      final String destPath = '${appDir.path}/$fileName';

      c.log('正在复制模型文件...');
      await File(file.path!).copy(destPath);
      c.log('已复制到 $destPath');

      await c.prepareModel(destPath);
      c.log('模型加载成功！');
    } catch (e) {
      c.log('加载模型失败：$e');
    }
  }
}

class DebugConsole extends StatelessWidget {
  const DebugConsole({super.key, required this.onBench});
  final Future<void> Function() onBench;

  @override
  Widget build(BuildContext context) {
    final ChatController c = ChatController.instance;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Debug Console',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制全部',
                    icon: const Icon(Icons.copy_all),
                    onPressed: () async {
                      final List<String> logs = c.debugLogs.value;
                      if (logs.isEmpty) return;
                      final String text = logs.join('\n');
                      await Clipboard.setData(ClipboardData(text: text));
                    },
                  ),
                  IconButton(
                    tooltip: '清空',
                    icon: const Icon(Icons.delete_sweep),
                    onPressed: () => c.debugLogs.value = <String>[],
                  ),
                  IconButton(
                    tooltip: 'Bench',
                    icon: const Icon(Icons.speed),
                    onPressed: !c.isReady ? null : onBench,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<List<String>>(
                valueListenable: c.debugLogs,
                builder: (BuildContext context, List<String> logs, Widget? _) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: logs.length,
                    itemBuilder: (BuildContext context, int index) {
                      final String log = logs[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          log,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
