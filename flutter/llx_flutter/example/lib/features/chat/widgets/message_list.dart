import 'dart:async';

import 'package:flutter/material.dart';
import 'package:llx_flutter/llx_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../../chat_backend.dart';
import 'message_bubble.dart';

class MessageList extends StatelessWidget {
  const MessageList({
    super.key,
    required this.controller,
    required this.generationStream,
    required this.isGenerating,
    required this.messagesListenable,
  });

  final ScrollController controller;
  final Stream<ChatStreamEvent>? generationStream;
  final ValueListenable<bool> isGenerating;
  final ValueListenable<List<ChatMessage>> messagesListenable;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ChatMessage>>(
      valueListenable: messagesListenable,
      builder: (BuildContext context, List<ChatMessage> messages, Widget? _) {
        return ListView.builder(
          controller: controller,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (BuildContext context, int index) {
            final ChatMessage message = messages[index];
            final bool isLast = index == messages.length - 1;
            if (isLast &&
                message.role == 'assistant' &&
                isGenerating.value &&
                generationStream != null) {
              return StreamBuilder<ChatStreamEvent>(
                stream: generationStream,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<ChatStreamEvent> snapshot,
                    ) {
                      final String display =
                          (snapshot.hasData &&
                              !snapshot.data!.finished &&
                              snapshot.data!.content.isNotEmpty)
                          ? snapshot.data!.content
                          : message.content;
                      return MessageBubble(
                        message: ChatMessage(
                          role: 'assistant',
                          content: display,
                        ),
                        isLast: true,
                      );
                    },
              );
            }
            return MessageBubble(message: message, isLast: isLast);
          },
        );
      },
    );
  }
}
