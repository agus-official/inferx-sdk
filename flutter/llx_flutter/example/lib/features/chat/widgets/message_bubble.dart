import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:llx_flutter/llx_flutter.dart';
import '../../../design_system/tokens.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.isLast = false});

  final ChatMessage message;
  final bool isLast;

  Future<void> _copy(BuildContext context, String text) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == 'user';

    // Tool trace bubbles (for function calling demo)
    if (message.role == 'tool_call' || message.role == 'tool_result') {
      final bool isCall = message.role == 'tool_call';
      final ColorScheme scheme = Theme.of(context).colorScheme;
      final Color bg = isCall
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainerLow;
      final Color border = isCall ? scheme.primary : scheme.tertiary;
      final String title = isCall ? 'Tool Call' : 'Tool Result';
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s + 2),
        child: InkWell(
          onLongPress: () => _copy(context, message.content),
          borderRadius: BorderRadius.circular(AppRadius.m),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppRadius.m),
              border: Border(left: BorderSide(color: border, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message.content,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: InkWell(
          onLongPress: () => _copy(context, message.content),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.l),
            topRight: Radius.circular(AppRadius.l),
            bottomLeft: Radius.circular(AppRadius.l),
            bottomRight: Radius.circular(AppRadius.s),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.s + 2),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.m,
              vertical: AppSpacing.s + 2,
            ),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.l),
                topRight: Radius.circular(AppRadius.l),
                bottomLeft: Radius.circular(AppRadius.l),
                bottomRight: Radius.circular(AppRadius.s),
              ),
            ),
            child: MarkdownTheme(
              data: MarkdownThemeData(
                textStyle: const TextStyle(
                  fontSize: 14.0,
                  color: Colors.white70,
                ),
              ),
              child: MarkdownWidget(
                markdown: Markdown.fromString(message.content),
              ),
            ),
          ),
        ),
      );
    }

    // 助手消息：无边框、无背景、文章样式，占满屏宽并居中显示（块级居中，文本仍按正常排版）
    final double screenWidth = MediaQuery.of(context).size.width;
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: screenWidth),
        child: InkWell(
          onLongPress: () => _copy(context, message.content),
          child: Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.s + 2),
            padding: EdgeInsets.zero,
            decoration: const BoxDecoration(), // 无背景、无边框
            child: MarkdownTheme(
              data: MarkdownThemeData(
                textStyle: TextStyle(
                  fontSize: 16.0,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              child: MarkdownWidget(
                markdown: Markdown.fromString(message.content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
