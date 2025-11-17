#include "llx.h"
#include <stdio.h>
#include <string>
#include <vector>
#include <sstream>
#include <iostream>
#include <fstream>
#include <limits>

static std::string esc(const std::string &s)
{
    std::string o;
    o.reserve(s.size() + 16);
    for (char c : s)
    {
        switch (c)
        {
        case '\\':
            o += "\\\\";
            break;
        case '"':
            o += "\\\"";
            break;
        case '\n':
            o += "\\n";
            break;
        case '\r':
            o += "\\r";
            break;
        case '\t':
            o += "\\t";
            break;
        default:
            o += c;
        }
    }
    return o;
}
static std::string build_msgs(const std::vector<std::pair<std::string, std::string>> &hist)
{
    std::ostringstream os;
    os << "[";
    for (size_t i = 0; i < hist.size(); ++i)
    {
        if (i)
            os << ",";
        os << "{\"role\":\"" << hist[i].first << "\",\"content\":\"" << esc(hist[i].second) << "\"}";
    }
    os << "]";
    return os.str();
}

int main(int argc, char **argv)
{
    if (argc < 3)
    {
        std::cerr << "Usage: " << argv[0] << " --model /path/to/model.gguf [--ctx 8192] [--nlen 1024] [--json request.json]"
                  << " [--lora /path/to/adapter.gguf[:scale]] (repeatable) [--lora-scale 1.0]\n";
        return 1;
    }
    std::string model_path;
    int n_ctx = 8192;
    int n_len = 1024;
    std::string json_path;
    std::vector<std::pair<std::string, float>> lora_specs; // {path, scale}, scale=NaN 表示未显式设置
    for (int i = 1; i < argc; ++i)
    {
        std::string a = argv[i];
        if (a == "--model" && i + 1 < argc)
            model_path = argv[++i];
        else if (a == "--ctx" && i + 1 < argc)
            n_ctx = std::stoi(argv[++i]);
        else if (a == "--nlen" && i + 1 < argc)
            n_len = std::stoi(argv[++i]);
        else if (a == "--json" && i + 1 < argc)
            json_path = argv[++i];
        else if (a == "--lora" && i + 1 < argc)
        {
            std::string spec = argv[++i];
            // 允许 path[:scale]
            size_t pos = spec.find(':');
            if (pos == std::string::npos)
            {
                lora_specs.push_back({spec, std::numeric_limits<float>::quiet_NaN()});
            }
            else
            {
                std::string path = spec.substr(0, pos);
                std::string s = spec.substr(pos + 1);
                float sc = 1.0f;
                try { sc = std::stof(s); } catch (...) { sc = 1.0f; }
                lora_specs.push_back({path, sc});
            }
        }
        else if (a == "--lora-scale" && i + 1 < argc)
        {
            float sc = 1.0f;
            try { sc = std::stof(argv[++i]); } catch (...) { sc = 1.0f; }
            // 语义：应用到最近一次 --lora 且未显式带 scale 的条目
            if (!lora_specs.empty() && std::isnan(lora_specs.back().second))
            {
                lora_specs.back().second = sc;
            }
        }
    }
    if (model_path.empty())
    {
        std::cerr << "Missing --model\n";
        return 1;
    }

    llx_backend_init();

    llx_model *m = nullptr;
    if (!llx_model_load(model_path.c_str(), &m))
    {
        std::cerr << llx_last_error() << "\n";
        return 2;
    }

    llx_session_params p = llx_session_default_params();
    p.n_ctx = n_ctx;
    llx_session *s = nullptr;
    if (!llx_session_create(m, p, &s))
    {
        std::cerr << llx_last_error() << "\n";
        return 3;
    }

    std::cout << llx_system_info() << "\n";
    std::cout << "Model loaded: " << model_path << "\n";

    // 应用多个 LoRA（如果指定）
    for (const auto &it : lora_specs)
    {
        const std::string &path = it.first;
        float sc = std::isnan(it.second) ? 1.0f : it.second;
        if (!llx_session_add_lora(s, path.c_str(), sc))
        {
            std::cerr << "Load LoRA failed: " << path << ", err=" << llx_last_error() << "\n";
            llx_session_free(s);
            llx_model_free(m);
            llx_backend_free();
            return 6;
        }
        std::cout << "LoRA loaded: " << path << ", scale=" << sc << "\n";
    }

    // JSON 一次性模式
    if (!json_path.empty())
    {
        std::ifstream ifs(json_path);
        if (!ifs)
        {
            std::cerr << "Failed to open JSON: " << json_path << "\n";
            llx_session_free(s);
            llx_model_free(m);
            llx_backend_free();
            return 4;
        }
        std::ostringstream ss;
        ss << ifs.rdbuf();
        std::string req = ss.str();

        // 建议无状态：清 KV
        llx_session_kv_clear(s);

        std::vector<char> out(4 << 20, '\0');
        if (!llx_chat_complete_json(s, req.c_str(), out.data(), out.size()))
        {
            std::cerr << llx_last_error() << "\n";
            llx_session_free(s);
            llx_model_free(m);
            llx_backend_free();
            return 5;
        }
        std::cout << out.data() << "\n";

        llx_session_free(s);
        llx_model_free(m);
        llx_backend_free();
        return 0;
    }

    std::cout << "Enter /exit to quit.\n";

    std::vector<std::pair<std::string, std::string>> hist;
    char buf[4096];

    while (true)
    {
        std::cout << "\nYou: " << std::flush;
        std::string line;
        if (!std::getline(std::cin, line))
            break;
        if (line == "/exit")
            break;
        if (line.empty())
            continue;

        hist.push_back({"user", line});
        std::string msgs = build_msgs(hist);

        if (!llx_session_init_from_messages_json(s, msgs.c_str(), n_len))
        {
            std::cerr << "init_chat failed: " << llx_last_error() << "\n";
            continue;
        }

        std::cout << "Assistant: " << std::flush;
        std::string reply;
        while (true)
        {
            int finished = 0;
            if (!llx_session_step(s, n_len, buf, sizeof(buf), &finished))
            {
                std::cerr << "step failed: " << llx_last_error() << "\n";
                break;
            }
            if (buf[0])
            {
                std::cout << buf << std::flush;
                reply += buf;
            }
            if (finished)
                break;
        }
        std::cout << "\n";
        llx_session_kv_clear(s);
        if (!reply.empty())
            hist.push_back({"assistant", reply});
    }

    llx_session_free(s);
    llx_model_free(m);
    llx_backend_free();
    return 0;
}
