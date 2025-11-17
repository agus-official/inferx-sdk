import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'llx_flutter_platform_interface.dart';
import 'llx_flutter.dart';

/// An implementation of [LlxFlutterPlatform] that uses method channels.
class MethodChannelLlxFlutter extends LlxFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('llx_flutter');

  @override
  Future<void> initBackend() async {
    await methodChannel.invokeMethod<void>('initBackend');
  }

  @override
  Future<void> freeBackend() async {
    await methodChannel.invokeMethod<void>('freeBackend');
  }

  @override
  Future<int> modelLoad(String path) async {
    final result = await methodChannel.invokeMethod<int>('modelLoad', {
      'path': path,
    });
    return result ?? 0;
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    await methodChannel.invokeMethod<void>('modelFree', {
      'modelHandle': modelHandle,
    });
  }

  @override
  Future<int> sessionCreate(int modelHandle, int nCtx, int nThreads) async {
    final result = await methodChannel.invokeMethod<int>('sessionCreate', {
      'modelHandle': modelHandle,
      'nCtx': nCtx,
      'nThreads': nThreads,
    });
    return result ?? 0;
  }

  @override
  Future<void> sessionFree(int sessionHandle) async {
    await methodChannel.invokeMethod<void>('sessionFree', {
      'sessionHandle': sessionHandle,
    });
  }

  @override
  Future<int> sessionInitFromText(
    int sessionHandle,
    String text,
    bool formatChat,
    int nLen,
  ) async {
    final result = await methodChannel
        .invokeMethod<int>('sessionInitFromText', {
          'sessionHandle': sessionHandle,
          'text': text,
          'formatChat': formatChat,
          'nLen': nLen,
        });
    return result ?? 0;
  }

  @override
  Future<int> sessionInitFromMessagesJson(
    int sessionHandle,
    String messagesJson,
    int nLen,
  ) async {
    final result = await methodChannel.invokeMethod<int>(
      'sessionInitFromMessagesJson',
      {
        'sessionHandle': sessionHandle,
        'messagesJson': messagesJson,
        'nLen': nLen,
      },
    );
    return result ?? 0;
  }

  @override
  Future<void> sessionKvClear(int sessionHandle) async {
    await methodChannel.invokeMethod<void>('sessionKvClear', {
      'sessionHandle': sessionHandle,
    });
  }

  @override
  Future<StepResult> sessionStep(int sessionHandle, int nLen) async {
    final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'sessionStep',
      {'sessionHandle': sessionHandle, 'nLen': nLen},
    );
    return StepResult.fromMap(result ?? {});
  }

  @override
  Future<String> chatCompleteJson(int sessionHandle, String requestJson) async {
    final result = await methodChannel.invokeMethod<String>(
      'chatCompleteJson',
      {'sessionHandle': sessionHandle, 'requestJson': requestJson},
    );
    return result ?? '';
  }

  @override
  Future<String> systemInfo() async {
    final result = await methodChannel.invokeMethod<String>('systemInfo');
    return result ?? '';
  }

  @override
  Future<String> bench(
    int sessionHandle,
    int pp,
    int tg,
    int pl,
    int nr,
  ) async {
    final result = await methodChannel.invokeMethod<String>('bench', {
      'sessionHandle': sessionHandle,
      'pp': pp,
      'tg': tg,
      'pl': pl,
      'nr': nr,
    });
    return result ?? '';
  }

  @override
  Future<bool> sessionLoadLora(
    int sessionHandle,
    String loraPath,
    double scale,
  ) async {
    final result = await methodChannel.invokeMethod<bool>('sessionLoadLora', {
      'sessionHandle': sessionHandle,
      'loraPath': loraPath,
      'scale': scale,
    });
    return result ?? false;
  }

  @override
  Future<bool> sessionAddLora(
    int sessionHandle,
    String loraPath,
    double scale,
  ) async {
    final result = await methodChannel.invokeMethod<bool>('sessionAddLora', {
      'sessionHandle': sessionHandle,
      'loraPath': loraPath,
      'scale': scale,
    });
    return result ?? false;
  }

  @override
  Future<bool> sessionUpdateLoraScale(
    int sessionHandle,
    String loraPath,
    double scale,
  ) async {
    final result = await methodChannel.invokeMethod<bool>(
      'sessionUpdateLoraScale',
      {'sessionHandle': sessionHandle, 'loraPath': loraPath, 'scale': scale},
    );
    return result ?? false;
  }

  @override
  Future<void> sessionRemoveLora(int sessionHandle, String loraPath) async {
    await methodChannel.invokeMethod<void>('sessionRemoveLora', {
      'sessionHandle': sessionHandle,
      'loraPath': loraPath,
    });
  }

  @override
  Future<void> sessionClearLora(int sessionHandle) async {
    await methodChannel.invokeMethod<void>('sessionClearLora', {
      'sessionHandle': sessionHandle,
    });
  }

  @override
  Future<String> lastError() async {
    final result = await methodChannel.invokeMethod<String>('lastError');
    return result ?? '';
  }
}
