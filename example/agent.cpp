#include "llx.h"
#include <string>
#include <vector>
#include <iostream>
#include <sstream>
#include <fstream>
#include <map>
#include <cstdlib>
#include <cctype>
#include <nlohmann/json.hpp>

// A simple local Agent demo (mental health coaching scenario) with function calling (mock tools)
// - Prints raw request JSON and raw response JSON
// - The model decides whether to call tools; the program executes tools and feeds results back
// - Multi-turn conversation loop

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
    // Very naive "sentiment" heuristic from the raw arguments JSON string.
    std::string mood = "neutral";
    double score = 0.0;
    auto s = args_json;
    for (auto &c : s) c = (char)std::tolower((unsigned char)c);
    if (s.find("stress") != std::string::npos || s.find("anxious") != std::string::npos || s.find("anxiety") != std::string::npos
        || s.find("overwhelmed") != std::string::npos || s.find("panic") != std::string::npos) {
        mood = "anxious"; score = -0.6;
    } else if (s.find("sad") != std::string::npos || s.find("depressed") != std::string::npos || s.find("hopeless") != std::string::npos) {
        mood = "sad"; score = -0.7;
    } else if (s.find("happy") != std::string::npos || s.find("grateful") != std::string::npos || s.find("excited") != std::string::npos) {
        mood = "happy"; score = 0.8;
    }
    std::ostringstream os;
    os << "{\"mood\":\"" << mood << "\",\"score\":" << score << "}";
    return os.str();
}

static std::string tool_suggest_coping_strategies(const std::string &args_json) {
    std::string mood = (args_json.find("anxious") != std::string::npos) ? "anxious" :
                       (args_json.find("sad") != std::string::npos) ? "sad" : "neutral";
    std::string list = (mood == "anxious")
        ? "[\"Box breathing (4-4-4-4)\",\"Write down triggers and thoughts\",\"Talk to a trusted friend\"]"
        : (mood == "sad")
            ? "[\"Take a short walk outside\",\"Do one small, achievable task\",\"Reach out to someone you trust\"]"
            : "[\"Keep a regular sleep schedule\",\"Light exercise\",\"Drink water and take breaks\"]";
    return std::string("{\"strategies\":") + list + "}";
}

static std::string tool_schedule_followup(const std::string &args_json) {
    // Always succeeds (mock).
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
    int max_tool_calls,
    bool parse_tool_calls,
    const std::string &tool_choice,
    const std::string &tool_format
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
    if (!tool_format.empty()) {
        os << "  \"tool_format\": \"" << tool_format << "\",\n";
    }
    os << "  \"temperature\": " << temperature << ",\n";
    os << "  \"top_p\": " << top_p << ",\n";
    os << "  \"top_k\": " << top_k << ",\n";
    os << "  \"max_tokens\": " << max_tokens << ",\n";
    // FunctionGemma stop sequences (Ollama-compatible):
    // - Always stop when the model starts emitting a tool response (the program should provide real tool output).
    // - If we only want 1 tool call, also stop right after the first </end_function_call>.
    if (tool_format == "functiongemma") {
        if (max_tool_calls == 1) {
            os << "  \"stop\": [\"<end_function_call>\", \"<start_function_response>\"],\n";
        } else {
            os << "  \"stop\": [\"<start_function_response>\"],\n";
        }
    }
    if (max_tool_calls > 0) {
        os << "  \"max_tool_calls\": " << max_tool_calls << ",\n";
    }
    os << "  \"parse_tool_calls\": " << (parse_tool_calls ? "true" : "false") << "\n";
    os << "}";
    return os.str();
}

static std::string system_prompt() {
    // Router-style prompt (optimized for small tool-calling models like FunctionGemma).
    // Goal: reduce free-form behavior and make tool usage predictable.
    return "{\"role\":\"system\",\"content\":\"You are a CLI assistant for a mental health coaching demo. You must be STRICT and predictable.\\n\\n"
           "Your core job: for each user message, do EXACTLY ONE action.\\n\\n"
           "Available tools (these are the ONLY valid function names you may ever call):\\n"
           "1) sentiment_analyze(text: string)\\n"
           "2) suggest_coping_strategies(mood: string)\\n"
           "3) schedule_followup(date: string)\\n\\n"
           "Important: There is NO tool named 'assess_mood', 'coping_plan', 'empathic_support', or 'clarify'. Those are NOT tools.\\n"
           "If you need to assess mood, you MUST call sentiment_analyze(text).\\n\\n"
           "Decide ONE of these actions per turn:\\n"
           "A) Plain response (no tool): Give a short supportive reply OR ask 1-2 key questions if unclear.\\n"
           "B) Call ONE tool exactly once: choose from the tool list above.\\n\\n"
           "Tool calling rules (be strict):\\n"
           "- If you call a tool, output ONLY the function call. No extra words.\\n"
           "- Never call an unknown function. If the needed function is not in the tool list, ask a question instead.\\n"
           "- Never invent tool results. The program will provide tool results in a tool message.\\n"
           "- NEVER output <start_function_response> or any tool response content.\\n\\n"
           "Safety: If the user expresses self-harm intent, imminent danger, or medical emergency, do NOT call tools. Provide brief, safety-first guidance and encourage contacting local emergency services or trusted help immediately.\"}";
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
        std::cerr << "Usage: " << argv[0] << " --model /path/to/model.gguf [--name functiongemma] [--tool_format auto|openai|functiongemma] [--max_tool_calls 1] [--ctx 16384] [--max_tokens 1024] [--temp 0.7] [--top_p 0.9] [--top_k 40]\n";
        return 1;
    }
    std::string model_path;
    std::string model_name = "local-llm";
    std::string tool_format = "auto";
    int ctx_len = 16384;
    int max_tokens = 1024;
    int max_tool_calls = 0; // 0 = unlimited
    double temperature = 0.7;
    double top_p = 0.9;
    int top_k = 40;

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--model" && i + 1 < argc) model_path = argv[++i];
        else if (a == "--name" && i + 1 < argc) model_name = argv[++i];
        else if (a == "--tool_format" && i + 1 < argc) tool_format = argv[++i];
        else if (a == "--max_tool_calls" && i + 1 < argc) max_tool_calls = std::atoi(argv[++i]);
        else if (a == "--ctx" && i + 1 < argc) ctx_len = std::atoi(argv[++i]);
        else if (a == "--max_tokens" && i + 1 < argc) max_tokens = std::atoi(argv[++i]);
        else if (a == "--temp" && i + 1 < argc) temperature = std::atof(argv[++i]);
        else if (a == "--top_p" && i + 1 < argc) top_p = std::atof(argv[++i]);
        else if (a == "--top_k" && i + 1 < argc) top_k = std::atoi(argv[++i]);
    }
    if (model_path.empty()) { std::cerr << "Missing --model\n"; return 1; }
    // For FunctionGemma, default to single tool call unless explicitly overridden.
    if (max_tool_calls <= 0 && tool_format == "functiongemma") {
        max_tool_calls = 1;
    }

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
    std::cout << "Agent ready. Type /exit to quit.\n";

    // Conversation history (OpenAI messages JSON fragments)
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

        // Append user message
        {
            std::ostringstream os;
            os << "{\"role\":\"user\",\"content\":\"";
            // Minimal escaping
            for (char c : user_in) {
                if (c == '\\') os << "\\\\";
                else if (c == '"') os << "\\\"";
                else if (c == '\n') os << "\\n";
                else os << c;
            }
            os << "\"}";
            messages.push_back(os.str());
        }

        // Drive one turn: may trigger tool use loops until the model stops requesting tools
        for (int iter = 0; iter < 8; ++iter) {
            // Build request
            std::string req = build_request_json(
                messages, tools, model_name,
                /*temperature=*/temperature, /*top_p=*/top_p, /*top_k=*/top_k,
                /*max_tokens=*/max_tokens, /*max_tool_calls=*/max_tool_calls,
                /*parse_tool_calls=*/true, /*tool_choice=*/"auto", /*tool_format=*/tool_format);

            // Print raw request JSON
            std::cout << "\n[Request]" << std::endl;
            std::cout << req << std::endl;

            // For a "stateless" demo we clear KV. Comment this out to keep KV across turns.
            llx_session_kv_clear(s);

            // Run
            std::vector<char> out(4 << 20, '\0');
            if (!llx_chat_complete_json(s, req.c_str(), out.data(), out.size())) {
                std::cerr << "error: " << llx_last_error() << "\n";
                break;
            }

            std::string resp = out.data();
            std::cout << "[Response]" << std::endl;
            std::cout << resp << std::endl;

            // Parse JSON, handle tool_calls, and continue the loop
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
                    // 1) Append assistant message (with tool_calls)
                    messages.push_back(msg.dump());

                    // 2) Execute tools and append role=tool results
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
                            // Some templates (e.g. FunctionGemma) require tool response name for rendering.
                            {"name", name},
                            {"tool_call_id", id},
                            {"content", tool_result}
                        };
                        messages.push_back(tool_msg.dump());
                    }
                    // 3) Continue: let the model answer based on tool results (or request more tools)
                    continue;
                }

                // No tool_calls: final assistant message
                messages.push_back(msg.dump());
                break;
            } catch (...) {
                // Parse failed: fall back to a placeholder assistant message
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
