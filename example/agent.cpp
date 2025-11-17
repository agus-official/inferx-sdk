#include "llx.h"
#include <string>
#include <vector>
#include <iostream>
#include <sstream>
#include <fstream>
#include <map>
#include <cstdlib>
#include <nlohmann/json.hpp>

// 一个简单的本地 Agent：心理咨询场景，支持 function calling（mock 工具）
// - 展示发给模型的原始 JSON 与模型返回的原始 JSON
// - 由模型（tool calls）驱动是否需要调用工具，随后把工具结果回填到 messages 中继续
// - 用户可持续多轮对话

static std::string read_file(const std::string &path) {
    std::ifstream ifs(path);
    std::ostringstream ss;
    ss << ifs.rdbuf();
    return ss.str();
}

static std::string trim(const std::string &s) {
    size_t b = s.find_first_not_of(" \t\r\n");
    if (b == std::string::npos) return "";
    size_t e = s.find_last_not_of(" \t\r\n");
    return s.substr(b, e - b + 1);
}

// 工具注册表（mock）：
// - sentiment_analyze(text) -> { mood, score }
// - suggest_coping_strategies(mood) -> { strategies: [...] }
// - schedule_followup(date) -> { ok: true }

static std::string tool_sentiment_analyze(const std::string &args_json) {
    // 极简解析：仅查找 "text":"..."
    std::string mood = "neutral";
    double score = 0.0;
    if (args_json.find("压力") != std::string::npos || args_json.find("焦虑") != std::string::npos) {
        mood = "anxious"; score = -0.6;
    } else if (args_json.find("开心") != std::string::npos) {
        mood = "happy"; score = 0.8;
    }
    std::ostringstream os;
    os << "{\"mood\":\"" << mood << "\",\"score\":" << score << "}";
    return os.str();
}

static std::string tool_suggest_coping_strategies(const std::string &args_json) {
    std::string mood = (args_json.find("anxious") != std::string::npos) ? "anxious" : "neutral";
    std::string list = (mood == "anxious")
        ? "[\"深呼吸练习\",\"记录触发因素\",\"和朋友聊聊\"]"
        : "[\"保持规律作息\",\"适度运动\"]";
    return std::string("{\"strategies\":") + list + "}";
}

static std::string tool_schedule_followup(const std::string &args_json) {
    // 总是成功
    return "{\"ok\":true}";
}

struct ToolFn { std::string name; std::string (*fn)(const std::string &); };

static std::map<std::string, ToolFn> kTools = {
    {"sentiment_analyze", {"sentiment_analyze", tool_sentiment_analyze}},
    {"suggest_coping_strategies", {"suggest_coping_strategies", tool_suggest_coping_strategies}},
    {"schedule_followup", {"schedule_followup", tool_schedule_followup}},
};

static std::string build_request_json(
    const std::vector<std::string> &messages_json_array,
    const std::string &tools_json,
    const std::string &model,
    double temperature,
    double top_p,
    int top_k,
    int max_tokens,
    bool parse_tool_calls,
    const std::string &tool_choice
) {
    std::ostringstream os;
    os << "{\n";
    os << "  \"model\": \"" << model << "\",\n";
    os << "  \"messages\": [\n";
    for (size_t i = 0; i < messages_json_array.size(); ++i) {
        if (i) os << ",\n";
        os << messages_json_array[i];
    }
    os << "\n  ],\n";
    if (!tools_json.empty()) {
        os << "  \"tools\": " << tools_json << ",\n";
        os << "  \"tool_choice\": \"" << tool_choice << "\",\n";
        os << "  \"parallel_tool_calls\": false,\n";
    }
    os << "  \"temperature\": " << temperature << ",\n";
    os << "  \"top_p\": " << top_p << ",\n";
    os << "  \"top_k\": " << top_k << ",\n";
    os << "  \"max_tokens\": " << max_tokens << ",\n";
    os << "  \"parse_tool_calls\": " << (parse_tool_calls ? "true" : "false") << "\n";
    os << "}";
    return os.str();
}

static std::string system_prompt() {
    return "{\"role\":\"system\",\"content\":\"你是一名专业的心理咨询助理。\\n- 在保证安全与尊重的前提下，引导用户表达情绪与需求。\\n- 当你需要更精确的帮助时，使用工具：sentiment_analyze 分析情绪，suggest_coping_strategies 给出应对建议，schedule_followup 预约跟进。\\n- 给出简洁、共情、可执行的建议。\"}";
}

static std::string tools_schema() {
    return "[\n"
           "  {\n"
           "    \"type\": \"function\",\n"
           "    \"function\": {\n"
           "      \"name\": \"sentiment_analyze\",\n"
           "      \"description\": \"Analyze user's emotional state from text\",\n"
           "      \"parameters\": {\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"}},\"required\":[\"text\"]}\n"
           "    }\n"
           "  },\n"
           "  {\n"
           "    \"type\": \"function\",\n"
           "    \"function\": {\n"
           "      \"name\": \"suggest_coping_strategies\",\n"
           "      \"description\": \"Suggest coping strategies by mood\",\n"
           "      \"parameters\": {\"type\":\"object\",\"properties\":{\"mood\":{\"type\":\"string\"}},\"required\":[\"mood\"]}\n"
           "    }\n"
           "  },\n"
           "  {\n"
           "    \"type\": \"function\",\n"
           "    \"function\": {\n"
           "      \"name\": \"schedule_followup\",\n"
           "      \"description\": \"Schedule a follow-up session\",\n"
           "      \"parameters\": {\"type\":\"object\",\"properties\":{\"date\":{\"type\":\"string\"}},\"required\":[\"date\"]}\n"
           "    }\n"
           "  }\n"
           "]";
}

int main(int argc, char **argv) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " --model /path/to/model.gguf [--ctx 16384] [--max_tokens 1024] [--temp 0.7] [--top_p 0.9] [--top_k 40]\n";
        return 1;
    }
    std::string model_path;
    int ctx_len = 16384;
    int max_tokens = 1024;
    double temperature = 0.7;
    double top_p = 0.9;
    int top_k = 40;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--model" && i + 1 < argc) model_path = argv[++i];
        else if (a == "--ctx" && i + 1 < argc) ctx_len = std::atoi(argv[++i]);
        else if (a == "--max_tokens" && i + 1 < argc) max_tokens = std::atoi(argv[++i]);
        else if (a == "--temp" && i + 1 < argc) temperature = std::atof(argv[++i]);
        else if (a == "--top_p" && i + 1 < argc) top_p = std::atof(argv[++i]);
        else if (a == "--top_k" && i + 1 < argc) top_k = std::atoi(argv[++i]);
    }
    if (model_path.empty()) { std::cerr << "Missing --model\n"; return 1; }

    llx_backend_init();

    llx_model *m = nullptr;
    if (!llx_model_load(model_path.c_str(), &m)) {
        std::cerr << llx_last_error() << "\n"; return 2;
    }

    llx_session_params p = llx_session_default_params();
    p.n_ctx = ctx_len;
    llx_session *s = nullptr;
    if (!llx_session_create(m, p, &s)) {
        std::cerr << llx_last_error() << "\n"; return 3;
    }

    std::cout << llx_system_info() << "\n";
    std::cout << "Agent ready. 输入 /exit 退出。\n";

    // 对话历史（OpenAI messages JSON 片段）
    std::vector<std::string> messages;
    messages.push_back(system_prompt());

    const std::string tools = tools_schema();

    while (true) {
        std::cout << "\nYou: " << std::flush;
        std::string user_in;
        if (!std::getline(std::cin, user_in)) break;
        user_in = trim(user_in);
        if (user_in == "/exit") break;
        if (user_in.empty()) continue;

        // 追加用户消息
        {
            std::ostringstream os;
            os << "{\"role\":\"user\",\"content\":\"";
            // 简易转义
            for (char c : user_in) {
                if (c == '\\') os << "\\\\";
                else if (c == '"') os << "\\\"";
                else if (c == '\n') os << "\\n";
                else os << c;
            }
            os << "\"}";
            messages.push_back(os.str());
        }

        // 驱动一个回合：可能触发多次 tool use，直到模型不再请求工具
        for (int iter = 0; iter < 8; ++iter) {
            // 构造请求
            std::string req = build_request_json(
                messages, tools, "local-llm",
                /*temperature=*/temperature, /*top_p=*/top_p, /*top_k=*/top_k,
                /*max_tokens=*/max_tokens, /*parse_tool_calls=*/true, /*tool_choice=*/"auto");

            // 展示发给模型的原始 JSON
            std::cout << "\n[Request]" << std::endl;
            std::cout << req << std::endl;

            // 为了演示“无状态”，这里清 KV；若希望保持上下文 KV，可注释掉下一行
            llx_session_kv_clear(s);

            // 执行
            std::vector<char> out(4 << 20, '\0');
            if (!llx_chat_complete_json(s, req.c_str(), out.data(), out.size())) {
                std::cerr << "error: " << llx_last_error() << "\n";
                break;
            }

            std::string resp = out.data();
            std::cout << "[Response]" << std::endl;
            std::cout << resp << std::endl;

            // 使用 JSON 解析，正确处理 tool_calls 并继续对话
            try {
                using json = nlohmann::ordered_json;
                json j = json::parse(resp);
                const auto & choices = j.at("choices");
                if (choices.empty()) {
                    messages.push_back("{\"role\":\"assistant\",\"content\":null}");
                    break;
                }
                const auto & msg = choices.at(0).at("message");

                if (msg.contains("tool_calls") && !msg.at("tool_calls").is_null()) {
                    // 1) 追加 assistant 消息（含 tool_calls）
                    messages.push_back(msg.dump());

                    // 2) 逐个执行工具，并把结果追加为 role=tool
                    for (const auto & tc : msg.at("tool_calls")) {
                        std::string id = tc.value("id", "call_0");
                        std::string name;
                        std::string args_str;
                        if (tc.contains("function")) {
                            const auto & fn = tc.at("function");
                            name = fn.value("name", "");
                            if (fn.contains("arguments")) {
                                if (fn.at("arguments").is_string()) args_str = fn.at("arguments").get<std::string>();
                                else args_str = fn.at("arguments").dump();
                            }
                        }

                        auto it = kTools.find(name);
                        std::string tool_result = std::string("{\"error\":\"unknown tool\"}");
                        if (it != kTools.end()) {
                            tool_result = it->second.fn(args_str);
                        }
                        json tool_msg = {
                            {"role", "tool"},
                            {"tool_call_id", id},
                            {"content", tool_result}
                        };
                        messages.push_back(tool_msg.dump());
                    }
                    // 3) 继续下一次迭代，让模型基于工具结果给出最终回答或继续 tool_calls
                    continue;
                }

                // 没有 tool_calls，当作最终 assistant 文本
                messages.push_back(msg.dump());
                break;
            } catch (...) {
                // 解析失败，回退为普通 assistant 占位
                messages.push_back("{\"role\":\"assistant\",\"content\":null}");
                break;
            }
        }
    }

    llx_session_free(s);
    llx_model_free(m);
    llx_backend_free();
    return 0;
}
