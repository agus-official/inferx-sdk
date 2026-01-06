# Cursor Rules — InferX

> 目标：为 Cursor 提供清晰的项目规则、当前架构梳理与未来演进方向，确保后续开发方向一致且可持续。

## 项目定位与愿景
- **定位**：在移动端（Android/iOS/Flutter）与低功耗设备（树莓派等）提供类似 **Ollama** 的本地 LLM 推理体验。
- **愿景**：
  - “开箱即用”的本地推理服务（模型管理、会话管理、工具调用、流式输出）。
  - 面向 **Agent 应用** 的高质量 Function Calling 能力（可验证、可扩展、跨模型适配）。
  - 以统一 C 接口为核心，向上提供多平台封装与易用 API。

## 当前架构与目录结构（必读）
- **核心后端（llama.cpp 封装）**
  - `third_party/llama.cpp/`：上游引擎（尽量不直接改）。
  - `src/llx.cpp`：核心实现（会话、流式、chat.completion JSON、tool_calls 解析主流程）。
  - `include/llx.h`：统一 C API（对外稳定接口）。
  - `src/tool_templates/`：**模型族 -> 工具调用策略**（tool_format/stop/解析器适配层，便于扩展更多模型族）。
    - `src/tool_templates/llx_tool_templates.{h,cpp}`：策略解析入口（auto resolver）。
    - `src/tool_templates/families/`：每个模型族一个文件（识别 + 必要的解析/策略）。
      - `functiongemma.cpp`：FunctionGemma 族识别 + `<start_function_call>...` tool_calls 解析。
      - `qwen.cpp`：Qwen 族识别（当前默认走 OpenAI-ish tool_calls；可在此细分 stop/解析策略）。

- **示例与工具**
  - `example/cli.cpp`：CLI 聊天与 JSON 请求示例。
  - `example/agent.cpp`：本地 Agent + function calling 演示（工具调用循环；**不再显式传 tool_format/stop**，由 SDK 自动策略处理）。

- **平台封装**
  - `android/llx-android/`：Android AAR + JNI/Kotlin 绑定。
  - `android/llx-example/`：Android 示例 App。
  - `ios/llx-ios/`：iOS Swift Package（CLLX/Native/Kit 三层封装）。
  - `ios/Example/InferxLLMExample/`：iOS 示例 App。
  - `flutter/llx_flutter/`：Flutter 插件与示例。
    - `flutter/llx_flutter/example/`：Flutter 示例 App（已移除 tool_format 下拉与手动 stop 注入；由 SDK 自动策略处理）。

- **文档**
  - `README.md` / `docs/README.zh-CN.md`：功能、架构、构建说明。

## 当前能力范围（事实基线）
- 支持 **普通 chat**（流式/非流式）、**LoRA 叠加**。
- **Function Calling**：
  - OpenAI 兼容格式（tools/tool_choice）。
  - FunctionGemma 特殊解析与 stop 序列处理（已迁移到 `src/tool_templates/families/functiongemma.cpp`）。
  - 解析工具调用并可限制 `max_tool_calls`。

## 跨平台调用约定（重要：避免“散装逻辑”回流到客户端）
目标：让 **Android/iOS/Flutter/CLI** 的调用方式尽可能一致、尽可能少的“模型特判”，把差异收敛在 SDK 内部的模型族策略层。

- **客户端不需要也不应该显式传 `tool_format`**
  - 正确做法：传 `model`（建议用文件名/别名/包含族信息的名称），SDK 内部通过模型族策略自动选择解析器与 stop。
  - 仍可选：如果你确实要 override（调试场景），可以保留 `tool_format` 字段，但示例默认不展示该参数。

- **客户端不需要手动拼 FunctionGemma stop**
  - 例如 `"<start_function_response>"`、`"<end_function_call>"` 这类 stop 序列由 SDK 内部策略自动追加。
  - 正确做法：只通过 `max_tool_calls` 控制“最多返回多少个 tool_calls”（例如 FunctionGemma 建议 `max_tool_calls=1`）。

- **客户端推荐保留的通用字段**
  - `tools` / `tool_choice` / `parallel_tool_calls` / `parse_tool_calls` / `max_tool_calls`
  - 采样相关：`temperature/top_p/top_k/seed`

## 如何新增一个模型族策略（扩展指南）
当你要支持新的模型族（例如 qwen3 的某种特定 tool 模板/stop/解析差异）：

1. 在 `src/tool_templates/families/` 新增 `xxx.cpp`
   - 实现 `bool llx_is_xxx_family(const std::string &model_name)`（识别规则：文件名/别名包含关键字）
   - 如果需要自定义解析器，也在该文件实现并在策略入口中选择
2. 在 `src/tool_templates/llx_tool_templates.cpp` 中把该族接入 `llx_resolve_tooling_policy(...)`
   - 配置 `format`（openai/functiongemma/未来更多）
   - 配置 `additional_stop_sequences`
3.（可选）补充示例与文档
   - `example/agent.cpp` / Flutter 示例只体现“通用字段”，避免新增客户端特判

## 开发规则（Cursor 行为指南）
1. **优先改动核心接口层**：业务新增功能优先落在 `src/llx.cpp` + `include/llx.h`，保持 C API 稳定与兼容。
2. **禁止随意改上游**：`third_party/llama.cpp` 仅在必要时改；尽量以适配层/包装层实现需求。
3. **跨平台一致性**：任何 API 变更必须同步更新 Android/iOS/Flutter 绑定与示例（最少更新 docs + 样例）。
4. **Tool/FC 调用必须可验证**：所有工具调用与解析都应有 schema 约束（详见未来规划）。
5. **示例即契约**：`example/` 下的示例是行为规范；API 变更需同步升级示例与 README。

## 未来演进路线（分阶段建议）

### 阶段 A：对齐 “Ollama 体验” 的本地推理能力
- 引入 **统一配置/模型注册机制**（模型别名、默认 chat 模板、工具能力标识）。
- 提供 **统一 CLI/API**，便于桌面/树莓派部署与调用。
- 建立简易 “模型元数据表”（用于判断 tool_format 与默认 stop 策略）。

### 阶段 B：Function Calling 强化（Agent 关键能力）
- **多模型 Function Calling 适配层**：
  - 参考 Ollama 的做法，针对不同模型族设置模板、stop 序列、解析策略。
  - 在 `llx_chat_complete_json` 中引入可扩展的 “model capability resolver”。
- **动态流式 JSON Schema 校验**：
  - 每个工具函数必须注册 JSON Schema（含可空/不可空、默认值）。
  - 在流式输出阶段实时解析并修复结构，确保最终返回 **合法 JSON**。
  - 引入 “schema-driven validator + repairer”，产物只落在 `tool_calls` 结构。

### 阶段 C：Ollama-like Microservice（llx serve）
- 新增类似 `ollama serve` 的微服务：
  - 提供 HTTP API（OpenAI 兼容 + 自定义管理接口）。
  - 模型管理、session 管理、tool schema 注册与热更新。
  - 支持本地/局域网使用，便于桌面开发/调试。

## 开发过程中建议关注的关键点
- `llx_chat_complete_json` 的工具解析主流程（请求解析 → 模板应用 → 生成 → 解析 → 组装响应）。
- `src/tool_templates/` 的模型族策略层（resolver、stop、解析器）。
- `src/tool_templates/families/functiongemma.cpp` 的 FunctionGemma tool_calls 解析与 stop 策略。
- `example/agent.cpp` 的工具调用循环（示例即契约；客户端尽量不做 tool_format/stop 特判）。

---

> **总结**：当前首要任务是明确项目结构并保证接口稳定；未来重点围绕 “Ollama 生态对齐” 与 “Function Calling 深化” 展开。
