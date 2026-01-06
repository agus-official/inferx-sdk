#pragma once

#include <string>
#include <vector>

#include "chat.h"

// 内部模块：模型族 -> tool calling 策略（format、stop、解析器）
// 注意：不是对外 C API 的一部分；仅供 src/llx.cpp 使用。

enum class llx_tool_format_kind {
    openai = 0,
    functiongemma = 1,
};

struct llx_tooling_policy {
    llx_tool_format_kind format = llx_tool_format_kind::openai;
    // 规范化后的名字（"openai"/"functiongemma"），便于调试/日志
    std::string format_name = "openai";
    // 需要额外叠加的 stop 序列（在 chat template additional_stops 与用户 stop 之后追加）
    std::vector<std::string> additional_stop_sequences;
};

// requested_tool_format: "auto"|"openai"|"functiongemma"（大小写不敏感；未知值按 auto 处理）
llx_tooling_policy llx_resolve_tooling_policy(const std::string &model_name,
                                              const std::string &requested_tool_format,
                                              bool has_tools,
                                              int max_tool_calls);

// FunctionGemma：从 <start_function_call>...<end_function_call> 抽出调用
std::vector<common_chat_tool_call> llx_parse_functiongemma_tool_calls(const std::string &text);


