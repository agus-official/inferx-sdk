/// 聊天消息
class ChatMessage {
  final String role;
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() {
    return {'role': role, 'content': content};
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String,
      content: json['content'] as String,
    );
  }

  @override
  String toString() => 'ChatMessage(role: $role, content: $content)';
}

/// LoRA 适配器信息
class LoraItem {
  final String path;
  final double scale;

  const LoraItem({required this.path, required this.scale});

  LoraItem copyWith({String? path, double? scale}) {
    return LoraItem(path: path ?? this.path, scale: scale ?? this.scale);
  }

  @override
  String toString() => 'LoraItem(path: $path, scale: $scale)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LoraItem && other.path == path && other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(path, scale);
}
