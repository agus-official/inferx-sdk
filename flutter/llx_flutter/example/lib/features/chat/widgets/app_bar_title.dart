import 'package:flutter/material.dart';
import '../../../chat_controller.dart';

class AppBarTitle extends StatelessWidget {
  const AppBarTitle({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ChatController controller = ChatController.instance;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ValueListenableBuilder<bool>(
            valueListenable: controller.isModelLoaded,
            builder: (BuildContext context, bool loaded, Widget? _) {
              final String title =
                  !loaded || controller.currentModelPath == null
                  ? '未加载模型'
                  : controller.currentModelPath!.split('/').last;
              return Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              );
            },
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
    );
  }
}
