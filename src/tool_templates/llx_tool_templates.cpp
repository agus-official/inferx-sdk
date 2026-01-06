#include "llx_tool_templates.h"

#include "families/llx_tool_families.h"

#include <cctype>

static std::string llx_to_lower_copy(std::string s) {
    for (auto &c : s) c = (char) std::tolower((unsigned char) c);
    return s;
}

static llx_tool_format_kind llx_parse_tool_format_kind(const std::string &s) {
    std::string v = llx_to_lower_copy(s);
    if (v == "functiongemma") return llx_tool_format_kind::functiongemma;
    return llx_tool_format_kind::openai;
}

llx_tooling_policy llx_resolve_tooling_policy(const std::string &model_name,
                                              const std::string &requested_tool_format,
                                              bool has_tools,
                                              int max_tool_calls) {
    llx_tooling_policy out;

    // 1) 显式指定优先生效
    std::string req = llx_to_lower_copy(requested_tool_format);
    if (req == "openai" || req == "functiongemma") {
        out.format = llx_parse_tool_format_kind(req);
    } else {
        // 2) auto：按模型族启发式选择（只影响 stop/parse，不影响 prompt 模板）
        if (has_tools && llx_is_functiongemma_family(model_name)) {
            out.format = llx_tool_format_kind::functiongemma;
        } else if (has_tools && llx_is_qwen_family(model_name)) {
            // qwen / qwen3 等：当前默认走 OpenAI-ish tool_calls（未来可在此细分 stop/解析策略）
            out.format = llx_tool_format_kind::openai;
        } else {
            out.format = llx_tool_format_kind::openai;
        }
    }

    out.format_name = (out.format == llx_tool_format_kind::functiongemma) ? "functiongemma" : "openai";

    if (out.format == llx_tool_format_kind::functiongemma) {
        // 官方建议把 start_function_response 当作 stop
        out.additional_stop_sequences.push_back("<start_function_response>");
        // 若上层希望单次工具调用（max_tool_calls=1），则在第一个 call 结束就停，避免继续生成其它 call
        if (max_tool_calls == 1) {
            out.additional_stop_sequences.push_back("<end_function_call>");
        }
    }

    return out;
}


