import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../design_system/tokens.dart';

class MessageInput extends StatelessWidget {
  const MessageInput({
    super.key,
    required this.controller,
    required this.canSendListenable,
    required this.enabledBuilder,
    required this.isGenerating,
    required this.isLoadingModel,
    required this.onSend,
  });

  final TextEditingController controller;
  final Listenable canSendListenable;
  final bool Function() enabledBuilder;
  final ValueListenable<bool> isGenerating;
  final ValueListenable<bool> isLoadingModel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: AppShadow.elevationUp,
      ),
      child: ListenableBuilder(
        listenable: canSendListenable,
        builder: (BuildContext context, Widget? _) {
          final bool enabled = enabledBuilder();
          return Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: enabled ? '输入消息...' : '请先加载模型（点击顶部）',
                  ),
                  maxLines: null,
                  enabled: enabled,
                  onSubmitted: (_) => enabled ? onSend() : null,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                height: 44,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  onPressed: enabled ? onSend : null,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: isGenerating,
                    builder:
                        (BuildContext context, bool generating, Widget? __) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: isLoadingModel,
                            builder:
                                (
                                  BuildContext context,
                                  bool loading,
                                  Widget? ___,
                                ) {
                                  if (generating || loading) {
                                    return const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    );
                                  }
                                  return const Icon(Icons.send_rounded);
                                },
                          );
                        },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
