import SwiftUI
import UniformTypeIdentifiers
import InferxLLMKit

struct ContentView: View {
    @State private var modelURL: URL? = nil
    @State private var composing: String = ""
    @State private var output: String = ""
    @State private var isLoading: Bool = false
    @State private var errorText: String? = nil
    // LoRA
    private struct LoraItem: Identifiable {
        let id = UUID()
        let path: String
        let displayName: String
        var scale: Float
    }
    @State private var loraURL: URL? = nil
    @State private var loras: [LoraItem] = []

    @State private var model: InferxModel? = nil
    @State private var session: InferxSession? = nil
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating: Bool = false
    @State private var showSettings: Bool = false
    @FocusState private var isComposingFocused: Bool
    // 统一文件选择器
    private enum ImportTarget { case model, lora }
    @State private var activeImportTarget: ImportTarget? = nil
    @State private var showFileImporter: Bool = false
    @State private var reopenSettingsAfterPicker: Bool = false

    private enum Role { case user, assistant }
    private struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
    }
    @State private var chatHistory: [[String: String]] = []

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏：模型状态与操作
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model != nil ? "模型已加载" : "未加载模型")
                        .font(.headline)
                    Text(modelURL?.lastPathComponent ?? "未选择模型")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("选择模型…") {
                    activeImportTarget = .model
                    showFileImporter = true
                }
                Button(isLoading ? "加载中…" : "加载模型") { loadModel() }
                    .disabled(isLoading || modelURL == nil)
                Button("设置") { showSettings = true }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { msg in
                            HStack {
                                if msg.role == .assistant { Spacer(minLength: 40) }
                                Text(msg.text)
                                    .padding(10)
                                    .background(msg.role == .user ? Color.accentColor.opacity(0.15) : Color(UIColor.secondarySystemBackground))
                                    .foregroundColor(.primary)
                                    .cornerRadius(12)
                                    .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: .leading)
                                if msg.role == .user { Spacer(minLength: 40) }
                            }
                            .id(msg.id)
                            .padding(.horizontal)
                        }
                        if isGenerating {
                            HStack {
                                Spacer(minLength: 40)
                                ProgressView().padding(.horizontal)
                                Spacer()
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { isComposingFocused = false }
                .onChange(of: messages.count) { _ in
                    if let lastId = messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // 底部输入栏
            HStack(alignment: .bottom, spacing: 8) {
                TextField("输入消息", text: $composing, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)
                    .disabled(session == nil || isGenerating)
                    .focused($isComposingFocused)
                Button(isGenerating ? "发送中…" : "发送") { sendMessage() }
                    .disabled(composing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session == nil || isGenerating)
            }
            .padding()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if activeImportTarget == .model {
                    self.modelURL = urls.first
                } else if activeImportTarget == .lora {
                    self.loraURL = urls.first
                    // 选择完成即添加 LoRA（默认 scale=1.0，可在列表中再调）
                    self.loraAddSelected()
                }
                self.activeImportTarget = nil
                if reopenSettingsAfterPicker {
                    self.showSettings = true
                    self.reopenSettingsAfterPicker = false
                }
            case .failure(let err):
                self.errorText = err.localizedDescription
                self.activeImportTarget = nil
                if reopenSettingsAfterPicker {
                    self.showSettings = true
                    self.reopenSettingsAfterPicker = false
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LoRA 适配器")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Button("选择 LoRA…") {
                        // 先收起设置面板，再弹出文件选择器，避免多层弹窗冲突
                        reopenSettingsAfterPicker = true
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            activeImportTarget = .lora
                            showFileImporter = true
                        }
                    }
                }
                // LoRA 列表与每项 scale 调整
                if loras.isEmpty {
                    Text("未加载任何 LoRA")
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(loras) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(item.displayName)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer()
                                    Button("移除") {
                                        loraRemove(path: item.path)
                                    }
                                }
                                HStack {
                                    Text("scale: \(String(format: "%.2f", item.scale))")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .frame(width: 96, alignment: .leading)
                                    Slider(
                                        value: Binding(
                                            get: { Double(item.scale) },
                                            set: { newVal in
                                                let newScale = max(0.05, min(2.0, Float(newVal)))
                                                loraSetScale(path: item.path, scale: newScale)
                                            }
                                        ),
                                        in: 0.05...2.0
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Divider()
                HStack {
                    Button("释放模型") { unloadModel() }.disabled(model == nil)
                    Button("清空 LoRA") { loraClear() }.disabled(session == nil || loras.isEmpty)
                    Spacer()
                    Button("关闭") { showSettings = false }
                }
            }
            .padding()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func loadModel() {
        errorText = nil
        isLoading = true
        DispatchQueue.global().async {
            do {
                guard let url = modelURL else { throw NSError(domain: "InferxLLMKit", code: -100, userInfo: [NSLocalizedDescriptionKey: "未选择模型"]) }
                var finalURL = url
                // 将文件复制到沙盒 Documents/models，确保后续可稳定读取
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let modelsDir = docs.appendingPathComponent("models", isDirectory: true)
                try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
                let dst = modelsDir.appendingPathComponent(url.lastPathComponent)
                let hasScope = url.startAccessingSecurityScopedResource()
                defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }
                try FileManager.default.copyItem(at: url, to: dst)
                finalURL = dst
                guard FileManager.default.isReadableFile(atPath: finalURL.path) else {
                    throw NSError(domain: "InferxLLMKit", code: -101, userInfo: [NSLocalizedDescriptionKey: "模型文件不可读或复制失败"])
                }
                let m = try InferxModel(path: finalURL.path)
                let s = try m.createSession()
                DispatchQueue.main.async {
                    self.model = m
                    self.session = s
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorText = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func unloadModel() {
        session = nil
        model = nil
    }

    private func sanitizeChunk(_ s: String) -> String {
        var t = s
        // 移除常见模板标签/角色标记
        let patterns = [
            "<|assistant|>", "<|user|>", "<|system|>",
            "<|start_header_id|>", "<|end_header_id|>",
            "<|eot_id|>", "<|end|>", "<|end_of_text|>", "<|im_end|>",
            "ASSISTANT:", "USER:", "System:"
        ]
        for p in patterns { t = t.replacingOccurrences(of: p, with: "") }
        return t
    }

    private func sendMessage() {
        guard let s = session else {
            errorText = "请先加载模型"
            return
        }
        let prompt = composing.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        composing = ""
        messages.append(ChatMessage(role: .user, text: prompt))
        isGenerating = true
        // 构造 messages JSON（OpenAI 兼容）并用模板预填充，然后流式 Step
        chatHistory.append(["role": "user", "content": prompt])
        let msgsArray = chatHistory
        do {
            let data = try JSONSerialization.data(withJSONObject: msgsArray, options: [])
            guard let msgsJson = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "InferxLLMKit", code: -303, userInfo: [NSLocalizedDescriptionKey: "消息序列化失败"])
            }
            try s.initFromMessagesJSON(msgsJson, maxLen: 1024)
        } catch {
            errorText = error.localizedDescription
            isGenerating = false
            return
        }
        var assistantMsg = ChatMessage(role: .assistant, text: "")
        messages.append(assistantMsg)
        let currentId = assistantMsg.id
        DispatchQueue.global().async {
            var steps = 0
            let maxSteps = 2048
            while true {
                do {
                    let (chunkRaw, finished) = try s.step(maxLen: 1024)
                    // 额外检测 Llama-3 会话结束标记，避免模型继续输出下一轮 header 导致表象“循环”
                    let stopMarkers = [
                        "<|eot_id|>", "<|end|>", "<|end_of_text|>", "<|im_end|>",
                        "<|EOT|>", "<|END_OF_TURN_TOKEN|>", "<|end_of_turn|>", "<|endoftext|>"
                    ]
                    let shouldStop = stopMarkers.first(where: { chunkRaw.contains($0) }) != nil
                    let chunk = self.sanitizeChunk(chunkRaw)
                    DispatchQueue.main.async {
                        if let idx = self.messages.firstIndex(where: { $0.id == currentId }) {
                            self.messages[idx].text += chunk
                        }
                        if finished || shouldStop {
                            self.isGenerating = false
                        }
                    }
                    if finished || shouldStop { break }
                    steps += 1
                    if steps > maxSteps {
                        DispatchQueue.main.async { self.isGenerating = false }
                        break
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorText = error.localizedDescription
                        self.isGenerating = false
                    }
                    break
                }
            }
            DispatchQueue.main.async {
                let reply = (self.messages.last?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !reply.isEmpty {
                    self.chatHistory.append(["role": "assistant", "content": reply])
                }
                self.session?.clearKV()
            }
        }
    }

    private func stepOnce() {
        guard let s = session else { return }
        do {
            let (chunk, finished) = try s.step(maxLen: 1024)
            output += chunk
            if finished {
                output += "\n[完成]"
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func clearKV() {
        session?.clearKV()
    }

    // MARK: - LoRA ops
    private func loraDst(for url: URL) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("lora", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 为避免不同目录同名 LoRA 相互覆盖，加上短 UUID 前缀
        let uuid = UUID().uuidString.prefix(8)
        return dir.appendingPathComponent("\(uuid)_\(url.lastPathComponent)")
    }
    private func ensureLocalLoraURL() throws -> URL {
        guard let url = loraURL else { throw NSError(domain: "InferxLLMKit", code: -200, userInfo: [NSLocalizedDescriptionKey: "未选择 LoRA"]) }
        let hasScope = url.startAccessingSecurityScopedResource()
        defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
        let dst = loraDst(for: url)
        // 使用唯一目的路径，不再移除同名
        try FileManager.default.copyItem(at: url, to: dst)
        guard FileManager.default.isReadableFile(atPath: dst.path) else {
            throw NSError(domain: "InferxLLMKit", code: -201, userInfo: [NSLocalizedDescriptionKey: "LoRA 文件不可读或复制失败"])
        }
        return dst
    }
    private func loraAddSelected(defaultScale: Float = 1.0) {
        guard let s = session else { return }
        if isGenerating { errorText = "正在生成中，稍后再添加 LoRA"; return }
        DispatchQueue.global().async {
            do {
                let url = try ensureLocalLoraURL()
                try s.addLora(path: url.path, scale: defaultScale)
                DispatchQueue.main.async {
                    let display = URL(fileURLWithPath: url.lastPathComponent).lastPathComponent
                    loras.append(LoraItem(path: url.path, displayName: display, scale: defaultScale))
                    // 切换 LoRA 后清 KV，确保新权重生效
                    session?.clearKV()
                    // 提示
                    messages.append(ChatMessage(role: .assistant, text: "已加载 LoRA: \(url.lastPathComponent), scale=\(String(format: "%.2f", defaultScale))"))
                }
            } catch {
                DispatchQueue.main.async { errorText = error.localizedDescription }
            }
        }
    }
    private func loraSetScale(path: String, scale: Float) {
        guard let s = session else { return }
        if isGenerating { return }
        DispatchQueue.global().async {
            do {
                try s.updateLoraScale(path: path, scale: scale)
                DispatchQueue.main.async {
                    if let idx = loras.firstIndex(where: { $0.path == path }) {
                        loras[idx].scale = scale
                    }
                    session?.clearKV()
                }
            } catch {
                DispatchQueue.main.async { errorText = error.localizedDescription }
            }
        }
    }
    private func loraRemove(path: String) {
        guard let s = session else { return }
        if isGenerating { return }
        DispatchQueue.global().async {
            s.removeLora(path: path)
            DispatchQueue.main.async {
                if let idx = loras.firstIndex(where: { $0.path == path }) {
                    loras.remove(at: idx)
                }
                session?.clearKV()
            }
        }
    }
    private func loraClear() {
        DispatchQueue.global().async {
            session?.clearLora()
            DispatchQueue.main.async {
                loras = []
                session?.clearKV()
            }
        }
    }
}

#Preview {
    ContentView()
}
