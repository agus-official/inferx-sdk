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
  - `src/llx.cpp`：核心实现（会话、流式、tool parsing、stop 序列、FunctionGemma 解析）。
  - `include/llx.h`：统一 C API（对外稳定接口）。

- **示例与工具**
  - `example/cli.cpp`：CLI 聊天与 JSON 请求示例。
  - `example/agent.cpp`：本地 Agent + function calling 演示（工具调用循环）。

- **平台封装**
  - `android/llx-android/`：Android AAR + JNI/Kotlin 绑定。
  - `android/llx-example/`：Android 示例 App。
  - `ios/llx-ios/`：iOS Swift Package（CLLX/Native/Kit 三层封装）。
  - `ios/Example/InferxLLMExample/`：iOS 示例 App。
  - `flutter/llx_flutter/`：Flutter 插件与示例。

- **文档**
  - `README.md` / `docs/README.zh-CN.md`：功能、架构、构建说明。

## 当前能力范围（事实基线）
- 支持 **普通 chat**（流式/非流式）、**LoRA 叠加**。
- **Function Calling**：
  - OpenAI 兼容格式（tools/tool_choice）。
  - FunctionGemma 特殊解析与 stop 序列处理。
  - 解析工具调用并可限制 `max_tool_calls`。

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
- `llx_chat_complete_json` 的工具解析流程与 `tool_format` 逻辑。
- `parse_functiongemma_tool_calls` 与 stop 序列策略。
- `example/agent.cpp` 的工具调用循环（可作为功能调用增强的验证样本）。

---

> **总结**：当前首要任务是明确项目结构并保证接口稳定；未来重点围绕 “Ollama 生态对齐” 与 “Function Calling 深化” 展开。
