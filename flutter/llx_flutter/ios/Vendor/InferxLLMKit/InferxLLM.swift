import Foundation

// Swift will see llx_* via public_header_files exposed by the Pod; no bridging header needed.

public enum InferxBackend {
    public static func initBackend() { llx_backend_init() }
    public static func freeBackend() { llx_backend_free() }
    public static func systemInfo() -> String { if let c = llx_system_info() { return String(cString: c) }; return "" }
    public static func lastError() -> String { if let c = llx_last_error() { return String(cString: c) }; return "" }
}

public struct SessionParams {
    public var nCtx: Int32
    public var nThreads: Int32
    public init(nCtx: Int32 = 8192, nThreads: Int32 = 0) {
        self.nCtx = nCtx
        self.nThreads = nThreads
    }
}

public final class InferxModel {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        llx_backend_init()
        var m: OpaquePointer? = nil
        let ok = path.withCString { cpath in
            llx_model_load(cpath, &m)
        }
        guard ok != 0, let m else {
            let msg = String(cString: llx_last_error())
            throw NSError(domain: "InferxLLMKit", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        self.handle = m
    }

    deinit {
        if let h = handle { llx_model_free(h) }
    }

    public func createSession(params: SessionParams = SessionParams()) throws -> InferxSession {
        var p = llx_session_default_params()
        p.n_ctx = Int32(params.nCtx)
        p.n_threads = Int32(params.nThreads)
        var sess: OpaquePointer? = nil
        let ok = llx_session_create(self.handle, p, &sess)
        guard ok != 0, let sess else {
            let msg = String(cString: llx_last_error())
            throw NSError(domain: "InferxLLMKit", code: -2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return InferxSession(handle: sess)
    }
}

public final class InferxSession {
    private var handle: OpaquePointer?

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        if let h = handle { llx_session_free(h) }
    }

    public func initFromText(_ text: String, formatChat: Bool = true, maxLen: Int32 = 1024) throws -> Int {
        let tokCount = text.withCString { c in
            llx_session_init_from_text(self.handle, c, formatChat ? 1 : 0, maxLen)
        }
        guard tokCount != 0 else {
            let msg = String(cString: llx_last_error())
            throw NSError(domain: "InferxLLMKit", code: -3, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return Int(tokCount)
    }

    public func initFromMessagesJSON(_ messagesJSON: String, maxLen: Int32 = 1024) throws -> Int {
        let tokCount = messagesJSON.withCString { c in
            llx_session_init_from_messages_json(self.handle, c, maxLen)
        }
        guard tokCount != 0 else {
            let msg = String(cString: llx_last_error())
            throw NSError(domain: "InferxLLMKit", code: -3, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return Int(tokCount)
    }

    public func step(maxLen: Int32 = 1024) throws -> (String, finished: Bool) {
        var buf = [CChar](repeating: 0, count: 2048)
        var finished: Int32 = 0
        let ok = buf.withUnsafeMutableBufferPointer { bp in
            llx_session_step(self.handle, maxLen, bp.baseAddress, bp.count, &finished)
        }
        guard ok != 0 else {
            let msg = String(cString: llx_last_error())
            throw NSError(domain: "InferxLLMKit", code: -4, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        let text = String(cString: buf)
        return (text, finished != 0)
    }

    public func chatComplete(requestJSON: String) throws -> String {
        // Chat completion responses (especially with tool calling) can be fairly large.
        // Keep this in sync with Android JNI and C++ examples.
        var out = [CChar](repeating: 0, count: 4 * 1024 * 1024)
        let ok = requestJSON.withCString { c in
            out.withUnsafeMutableBufferPointer { bp in
                llx_chat_complete_json(self.handle, c, bp.baseAddress, bp.count)
            }
        }
        guard ok != 0 else {
            let msg = String(cString: llx_last_error())
            throw NSError(domain: "InferxLLMKit", code: -5, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return String(cString: out)
    }

    public func clearKV() {
        llx_session_kv_clear(self.handle)
    }

    // MARK: - LoRA
    @discardableResult
    public func loadLora(path: String, scale: Float) throws -> Bool {
        let ok = path.withCString { c in
            llx_session_load_lora(self.handle, c, scale)
        }
        if ok == 0 {
            let msg = String(cString: llx_last_error())
            throw NSError(domain: "InferxLLMKit", code: -6, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return true
    }

    @discardableResult
    public func addLora(path: String, scale: Float) throws -> Bool {
        let ok = path.withCString { c in
            llx_session_add_lora(self.handle, c, scale)
        }
        if ok == 0 {
            let msg = String(cString: llx_last_error())
            throw NSError(domain: "InferxLLMKit", code: -7, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return true
    }

    @discardableResult
    public func updateLoraScale(path: String, scale: Float) throws -> Bool {
        let ok = path.withCString { c in
            llx_session_update_lora_scale(self.handle, c, scale)
        }
        if ok == 0 {
            let msg = String(cString: llx_last_error())
            throw NSError(domain: "InferxLLMKit", code: -8, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return true
    }

    public func removeLora(path: String) {
        path.withCString { c in
            llx_session_remove_lora(self.handle, c)
        }
    }

    public func clearLora() {
        llx_session_clear_lora(self.handle)
    }

    // MARK: - Benchmarks
    public func bench(pp: Int32, tg: Int32, pl: Int32, nr: Int32) throws -> String {
        var out = [CChar](repeating: 0, count: 8 * 1024)
        let ok = out.withUnsafeMutableBufferPointer { bp in
            llx_bench(self.handle, pp, tg, pl, nr, bp.baseAddress, bp.count)
        }
        guard ok != 0 else {
            let msg = String(cString: llx_last_error())
            throw NSError(domain: "InferxLLMKit", code: -9, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return String(cString: out)
    }
}


