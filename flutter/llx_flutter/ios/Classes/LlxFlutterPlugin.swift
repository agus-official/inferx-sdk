import Flutter
import UIKit

// Import Swift kit module defined in ../../../ios/llx-ios/Sources
// 同一 Pod 目标内直接访问公开类型

public class LlxFlutterPlugin: NSObject, FlutterPlugin {
  private static var channelName = "llx_flutter"

  // Handle maps
  private var models: [Int64: InferxModel] = [:]
  private var sessions: [Int64: InferxSession] = [:]
  private var nextHandle: Int64 = 1
  private let queue = DispatchQueue(label: "com.inferx.llx_flutter.serial")

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = LlxFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initBackend":
      queue.async {
        InferxBackend.initBackend()
        DispatchQueue.main.async { result(nil) }
      }

    case "freeBackend":
      queue.async {
        InferxBackend.freeBackend()
        DispatchQueue.main.async { result(nil) }
      }

    case "modelLoad":
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "path is required", details: nil))
      }
      queue.async {
        do {
          let m = try InferxModel(path: path)
          let h = self.allocateHandle()
          self.models[h] = m
          DispatchQueue.main.async { result(h) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) }
        }
      }

    case "modelFree":
      guard let args = call.arguments as? [String: Any], let mh = (args["modelHandle"] as? NSNumber)?.int64Value else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "modelHandle is required", details: nil))
      }
      queue.async {
        self.models.removeValue(forKey: mh)
        DispatchQueue.main.async { result(nil) }
      }

    case "sessionCreate":
      guard let args = call.arguments as? [String: Any],
            let mh = (args["modelHandle"] as? NSNumber)?.int64Value,
            let model = models[mh] else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "invalid args", details: nil))
      }
      let nCtx: Int32 = (args["nCtx"] as? NSNumber)?.int32Value ?? 8192
      let nThreads: Int32 = (args["nThreads"] as? NSNumber)?.int32Value ?? 0
      queue.async {
        do {
          let sess = try model.createSession(params: SessionParams(nCtx: nCtx, nThreads: nThreads))
          let sh = self.allocateHandle()
          self.sessions[sh] = sess
          DispatchQueue.main.async { result(sh) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) }
        }
      }

    case "sessionFree":
      guard let args = call.arguments as? [String: Any], let sh = (args["sessionHandle"] as? NSNumber)?.int64Value else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "sessionHandle is required", details: nil))
      }
      queue.async {
        self.sessions.removeValue(forKey: sh)
        DispatchQueue.main.async { result(nil) }
      }

    case "sessionInitFromText":
      guard let args = call.arguments as? [String: Any],
            let sh = (args["sessionHandle"] as? NSNumber)?.int64Value,
            let text = args["text"] as? String,
            let sess = sessions[sh] else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "invalid args", details: nil))
      }
      let formatChat = (args["formatChat"] as? NSNumber)?.boolValue ?? true
      let nLen = (args["nLen"] as? NSNumber)?.int32Value ?? 1024
      queue.async {
        do {
          let count = try sess.initFromText(text, formatChat: formatChat, maxLen: nLen)
          DispatchQueue.main.async { result(count) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) }
        }
      }

    case "sessionInitFromMessagesJson":
      guard let args = call.arguments as? [String: Any],
            let sh = (args["sessionHandle"] as? NSNumber)?.int64Value,
            let messagesJson = args["messagesJson"] as? String,
            let sess = sessions[sh] else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "invalid args", details: nil))
      }
      let nLen = (args["nLen"] as? NSNumber)?.int32Value ?? 1024
      queue.async {
        do {
          let count = try sess.initFromMessagesJSON(messagesJson, maxLen: nLen)
          DispatchQueue.main.async { result(count) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) }
        }
      }

    case "sessionKvClear":
      guard let args = call.arguments as? [String: Any], let sh = (args["sessionHandle"] as? NSNumber)?.int64Value, let sess = sessions[sh] else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "sessionHandle is required", details: nil))
      }
      queue.async {
        sess.clearKV()
        DispatchQueue.main.async { result(nil) }
      }

    case "sessionStep":
      guard let args = call.arguments as? [String: Any], let sh = (args["sessionHandle"] as? NSNumber)?.int64Value, let sess = sessions[sh] else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "sessionHandle is required", details: nil))
      }
      let nLen = (args["nLen"] as? NSNumber)?.int32Value ?? 1024
      queue.async {
        do {
          let (text, finished) = try sess.step(maxLen: nLen)
          DispatchQueue.main.async { result(["text": text, "finished": finished]) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) }
        }
      }

    case "chatCompleteJson":
      guard let args = call.arguments as? [String: Any], let sh = (args["sessionHandle"] as? NSNumber)?.int64Value, let sess = sessions[sh], let requestJson = args["requestJson"] as? String else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "invalid args", details: nil))
      }
      queue.async {
        do { let s = try sess.chatComplete(requestJSON: requestJson); DispatchQueue.main.async { result(s) } }
        catch { DispatchQueue.main.async { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) } }
      }

    case "systemInfo":
      queue.async { let s = InferxBackend.systemInfo(); DispatchQueue.main.async { result(s) } }

    case "bench":
      guard let args = call.arguments as? [String: Any], let sh = (args["sessionHandle"] as? NSNumber)?.int64Value, let sess = sessions[sh] else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "invalid args", details: nil))
      }
      let pp = (args["pp"] as? NSNumber)?.int32Value ?? 8
      let tg = (args["tg"] as? NSNumber)?.int32Value ?? 4
      let pl = (args["pl"] as? NSNumber)?.int32Value ?? 1
      let nr = (args["nr"] as? NSNumber)?.int32Value ?? 1
      queue.async {
        do { let s = try sess.bench(pp: pp, tg: tg, pl: pl, nr: nr); DispatchQueue.main.async { result(s) } }
        catch { DispatchQueue.main.async { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) } }
      }

    case "sessionLoadLora":
      guard let args = call.arguments as? [String: Any], let sh = (args["sessionHandle"] as? NSNumber)?.int64Value, let sess = sessions[sh], let loraPath = args["loraPath"] as? String else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "invalid args", details: nil))
      }
      let scale = (args["scale"] as? NSNumber)?.floatValue ?? 1.0
      queue.async {
        do { let ok = try sess.loadLora(path: loraPath, scale: scale); DispatchQueue.main.async { result(ok) } }
        catch { DispatchQueue.main.async { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) } }
      }

    case "sessionAddLora":
      guard let args = call.arguments as? [String: Any], let sh = (args["sessionHandle"] as? NSNumber)?.int64Value, let sess = sessions[sh], let loraPath = args["loraPath"] as? String else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "invalid args", details: nil))
      }
      let scale = (args["scale"] as? NSNumber)?.floatValue ?? 1.0
      queue.async {
        do { let ok = try sess.addLora(path: loraPath, scale: scale); DispatchQueue.main.async { result(ok) } }
        catch { DispatchQueue.main.async { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) } }
      }

    case "sessionUpdateLoraScale":
      guard let args = call.arguments as? [String: Any], let sh = (args["sessionHandle"] as? NSNumber)?.int64Value, let sess = sessions[sh], let loraPath = args["loraPath"] as? String else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "invalid args", details: nil))
      }
      let scale = (args["scale"] as? NSNumber)?.floatValue ?? 1.0
      queue.async {
        do { let ok = try sess.updateLoraScale(path: loraPath, scale: scale); DispatchQueue.main.async { result(ok) } }
        catch { DispatchQueue.main.async { result(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil)) } }
      }

    case "sessionRemoveLora":
      guard let args = call.arguments as? [String: Any], let sh = (args["sessionHandle"] as? NSNumber)?.int64Value, let sess = sessions[sh], let loraPath = args["loraPath"] as? String else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "invalid args", details: nil))
      }
      queue.async {
        sess.removeLora(path: loraPath)
        DispatchQueue.main.async { result(nil) }
      }

    case "sessionClearLora":
      guard let args = call.arguments as? [String: Any], let sh = (args["sessionHandle"] as? NSNumber)?.int64Value, let sess = sessions[sh] else {
        return result(FlutterError(code: "INVALID_ARGUMENT", message: "sessionHandle is required", details: nil))
      }
      queue.async {
        sess.clearLora()
        DispatchQueue.main.async { result(nil) }
      }

    case "lastError":
      queue.async { let s = InferxBackend.lastError(); DispatchQueue.main.async { result(s) } }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func allocateHandle() -> Int64 { defer { nextHandle += 1 }; return nextHandle }
}


