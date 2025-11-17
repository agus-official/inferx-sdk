import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'llx_flutter_method_channel.dart';
import 'llx_flutter.dart';

abstract class LlxFlutterPlatform extends PlatformInterface {
  /// Constructs a LlxFlutterPlatform.
  LlxFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static LlxFlutterPlatform _instance = MethodChannelLlxFlutter();

  /// The default instance of [LlxFlutterPlatform] to use.
  ///
  /// Defaults to [MethodChannelLlxFlutter].
  static LlxFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LlxFlutterPlatform] when
  /// they register themselves.
  static set instance(LlxFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> initBackend() {
    throw UnimplementedError('initBackend() has not been implemented.');
  }

  Future<void> freeBackend() {
    throw UnimplementedError('freeBackend() has not been implemented.');
  }

  Future<int> modelLoad(String path) {
    throw UnimplementedError('modelLoad() has not been implemented.');
  }

  Future<void> modelFree(int modelHandle) {
    throw UnimplementedError('modelFree() has not been implemented.');
  }

  Future<int> sessionCreate(int modelHandle, int nCtx, int nThreads) {
    throw UnimplementedError('sessionCreate() has not been implemented.');
  }

  Future<void> sessionFree(int sessionHandle) {
    throw UnimplementedError('sessionFree() has not been implemented.');
  }

  Future<int> sessionInitFromText(
    int sessionHandle,
    String text,
    bool formatChat,
    int nLen,
  ) {
    throw UnimplementedError('sessionInitFromText() has not been implemented.');
  }

  Future<int> sessionInitFromMessagesJson(
    int sessionHandle,
    String messagesJson,
    int nLen,
  ) {
    throw UnimplementedError(
      'sessionInitFromMessagesJson() has not been implemented.',
    );
  }

  Future<void> sessionKvClear(int sessionHandle) {
    throw UnimplementedError('sessionKvClear() has not been implemented.');
  }

  Future<StepResult> sessionStep(int sessionHandle, int nLen) {
    throw UnimplementedError('sessionStep() has not been implemented.');
  }

  Future<String> chatCompleteJson(int sessionHandle, String requestJson) {
    throw UnimplementedError('chatCompleteJson() has not been implemented.');
  }

  Future<String> systemInfo() {
    throw UnimplementedError('systemInfo() has not been implemented.');
  }

  Future<String> bench(int sessionHandle, int pp, int tg, int pl, int nr) {
    throw UnimplementedError('bench() has not been implemented.');
  }

  Future<bool> sessionLoadLora(
    int sessionHandle,
    String loraPath,
    double scale,
  ) {
    throw UnimplementedError('sessionLoadLora() has not been implemented.');
  }

  Future<bool> sessionAddLora(
    int sessionHandle,
    String loraPath,
    double scale,
  ) {
    throw UnimplementedError('sessionAddLora() has not been implemented.');
  }

  Future<bool> sessionUpdateLoraScale(
    int sessionHandle,
    String loraPath,
    double scale,
  ) {
    throw UnimplementedError(
      'sessionUpdateLoraScale() has not been implemented.',
    );
  }

  Future<void> sessionRemoveLora(int sessionHandle, String loraPath) {
    throw UnimplementedError('sessionRemoveLora() has not been implemented.');
  }

  Future<void> sessionClearLora(int sessionHandle) {
    throw UnimplementedError('sessionClearLora() has not been implemented.');
  }

  Future<String> lastError() {
    throw UnimplementedError('lastError() has not been implemented.');
  }
}
