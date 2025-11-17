import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:llx_flutter/llx_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../chat_controller.dart';

class LoraSheet extends StatelessWidget {
  const LoraSheet({super.key});

  ChatController get _controller => ChatController.instance;

  Future<void> _pickAndAddLora(BuildContext context) async {
    if (!_controller.isReady) return;
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      final PlatformFile file = result.files.first;
      if (file.path == null) return;

      final Directory appDir = (Platform.isIOS || Platform.isMacOS)
          ? await getApplicationSupportDirectory()
          : (await getExternalStorageDirectory() ??
                await getApplicationDocumentsDirectory());
      final String fileName = file.name.endsWith('.gguf')
          ? file.name
          : '${file.name}.gguf';
      final String destPath = '${appDir.path}/$fileName';

      await File(file.path!).copy(destPath);
      await _controller.addOrUpdateLora(destPath, 1.0);
    } catch (e) {
      _controller.log('添加 LoRA 失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        builder: (BuildContext context, ScrollController controller) {
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'LoRA 配置',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickAndAddLora(context),
                      icon: const Icon(Icons.add),
                      label: const Text('添加 LoRA'),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<List<LoraItem>>(
                      valueListenable: _controller.loras,
                      builder:
                          (
                            BuildContext context,
                            List<LoraItem> loras,
                            Widget? _,
                          ) {
                            return OutlinedButton.icon(
                              onPressed: loras.isNotEmpty
                                  ? _controller.clearAllLora
                                  : null,
                              icon: const Icon(Icons.delete_sweep),
                              label: const Text('清空'),
                            );
                          },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ValueListenableBuilder<List<LoraItem>>(
                  valueListenable: _controller.loras,
                  builder: (BuildContext context, List<LoraItem> loras, Widget? _) {
                    return ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.all(16),
                      itemCount: loras.length,
                      itemBuilder: (BuildContext context, int index) {
                        final LoraItem lora = loras[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                        lora.path,
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () =>
                                          _controller.removeLora(lora.path),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: <Widget>[
                                    Text(
                                      'scale: ${lora.scale.toStringAsFixed(2)}',
                                    ),
                                    Expanded(
                                      child: Slider(
                                        value: lora.scale,
                                        min: 0.1,
                                        max: 2.0,
                                        onChanged: (double value) => _controller
                                            .addOrUpdateLora(lora.path, value),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
