#include "llx.h"

#include <string>
#include <sstream>
#include <vector>
#include <algorithm>
#include <unistd.h>

#include "llama.h"
#include "common.h"
#include "chat.h"
#include <nlohmann/json.hpp>
#include <ctime>

static thread_local std::string g_err;

static void set_err(const std::string &e) { g_err = e; }
extern "C" const char *llx_last_error(void) { return g_err.empty() ? "" : g_err.c_str(); }

// 前置声明，供早期使用
static bool is_valid_utf8(const std::string &s);

struct llx_model
{
    llama_model *m = nullptr;
};

struct llx_session
{
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
    struct lora_entry {
        std::string path;
        llama_adapter_lora *ptr = nullptr;
        float scale = 1.0f;
    };
    std::vector<lora_entry> loras;
    llama_batch batch{};
    llama_sampler *sampler = nullptr;
    common_chat_templates *chat = nullptr;
    std::string cached; // 缓存未拼满的 UTF-8 片段
    int ncur = 0;
    int n_ctx = 8192;
};

static int detect_threads()
{
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    if (n < 1)
        n = 1;
    int t = (int)n - 2;
    if (t < 1)
        t = 1;
    if (t > 8)
        t = 8;
    return t;
}

extern "C" void llx_backend_init(void)
{
    llama_backend_init();
}
extern "C" void llx_backend_free(void)
{
    llama_backend_free();
}
extern "C" const char *llx_system_info(void)
{
    return llama_print_system_info();
}

extern "C" int llx_model_load(const char *path, llx_model **out_model)
{
    if (!path || !out_model)
    {
        set_err("llx_model_load: invalid args");
        return 0;
    }
    *out_model = nullptr;

    llama_model_params mp = llama_model_default_params();
    llama_model *m = llama_model_load_from_file(path, mp);
    if (!m)
    {
        set_err("llx_model_load: llama_model_load_from_file failed");
        return 0;
    }

    auto *wrap = new llx_model();
    wrap->m = m;
    *out_model = wrap;
    return 1;
}

extern "C" void llx_model_free(llx_model *model)
{
    if (!model)
        return;
    if (model->m)
        llama_model_free(model->m);
    delete model;
}

extern "C" llx_session_params llx_session_default_params(void)
{
    llx_session_params p;
    p.n_ctx = 8192;
    p.n_threads = 0; // auto
    return p;
}

extern "C" int llx_session_create(llx_model *model, llx_session_params params, llx_session **out_sess)
{
    if (!model || !model->m || !out_sess)
    {
        set_err("llx_session_create: invalid args");
        return 0;
    }
    *out_sess = nullptr;

    int n_threads = params.n_threads <= 0 ? detect_threads() : params.n_threads;

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = params.n_ctx > 0 ? params.n_ctx : 8192;
    cp.n_threads = n_threads;
    cp.n_threads_batch = n_threads;

    llama_context *ctx = llama_init_from_model(model->m, cp);
    if (!ctx)
    {
        set_err("llx_session_create: llama_init_from_model failed");
        return 0;
    }

    llama_batch batch = llama_batch_init(cp.n_ctx, /*embd*/ 0, /*n_seq_max*/ 1);

    auto schain = llama_sampler_chain_default_params();
    schain.no_perf = true;
    llama_sampler *sampler = llama_sampler_chain_init(schain);
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

    auto chat = common_chat_templates_init(model->m, "", "", "").release();

    auto *s = new llx_session();
    s->model = model->m;
    s->ctx = ctx;
    s->batch = batch;
    s->sampler = sampler;
    s->chat = chat;
    s->n_ctx = cp.n_ctx;
    *out_sess = s;
    return 1;
}

extern "C" int llx_session_load_lora(llx_session *sess, const char *lora_path, float scale)
{
    if (!sess || !sess->ctx || !sess->model || !lora_path || !*lora_path)
    {
        set_err("llx_session_load_lora: invalid args");
        return 0;
    }
    // 清理全部已加载的 LoRA，然后按单个加载（兼容老接口）
    // 等价于：clear -> add
    // 清理
    if (!sess->loras.empty())
    {
        llama_clear_adapter_lora(sess->ctx);
        for (auto &e : sess->loras)
        {
            if (e.ptr) llama_adapter_lora_free(e.ptr);
        }
        sess->loras.clear();
    }
    // 加载并应用
    llama_adapter_lora *adapter = llama_adapter_lora_init(sess->model, lora_path);
    if (!adapter)
    {
        set_err("llx_session_load_lora: llama_adapter_lora_init failed");
        return 0;
    }
    if (scale <= 0.0f) scale = 1.0f;
    if (llama_set_adapter_lora(sess->ctx, adapter, scale) < 0)
    {
        llama_adapter_lora_free(adapter);
        set_err("llx_session_load_lora: llama_set_adapter_lora failed");
        return 0;
    }
    llx_session::lora_entry ent;
    ent.path = lora_path;
    ent.ptr = adapter;
    ent.scale = scale;
    sess->loras.push_back(ent);
    // 切换 LoRA 后清空 KV，避免旧上下文影响
    llama_memory_clear(llama_get_memory(sess->ctx), /*gain memory*/ true);
    return 1;
}

static void apply_all_loras(llx_session *sess)
{
    if (!sess || !sess->ctx) return;
    llama_clear_adapter_lora(sess->ctx);
    for (auto &e : sess->loras)
    {
        if (e.ptr)
        {
            llama_set_adapter_lora(sess->ctx, e.ptr, e.scale);
        }
    }
    // 应用 LoRA 变化后清 KV
    llama_memory_clear(llama_get_memory(sess->ctx), /*gain memory*/ true);
}

extern "C" int llx_session_add_lora(llx_session *sess, const char *lora_path, float scale)
{
    if (!sess || !sess->ctx || !sess->model || !lora_path || !*lora_path)
    {
        set_err("llx_session_add_lora: invalid args");
        return 0;
    }
    if (scale <= 0.0f) scale = 1.0f;

    // 若已存在同路径 -> 更新 scale
    for (auto &e : sess->loras)
    {
        if (e.path == lora_path)
        {
            e.scale = scale;
            apply_all_loras(sess);
            return 1;
        }
    }

    // 新加载
    llama_adapter_lora *adapter = llama_adapter_lora_init(sess->model, lora_path);
    if (!adapter)
    {
        set_err("llx_session_add_lora: llama_adapter_lora_init failed");
        return 0;
    }
    llx_session::lora_entry ent;
    ent.path = lora_path;
    ent.ptr = adapter;
    ent.scale = scale;
    sess->loras.push_back(ent);

    apply_all_loras(sess);
    return 1;
}

extern "C" int llx_session_update_lora_scale(llx_session *sess, const char *lora_path, float scale)
{
    if (!sess || !sess->ctx || !lora_path || !*lora_path)
    {
        set_err("llx_session_update_lora_scale: invalid args");
        return 0;
    }
    if (scale <= 0.0f) scale = 1.0f;
    for (auto &e : sess->loras)
    {
        if (e.path == lora_path)
        {
            e.scale = scale;
            apply_all_loras(sess);
            return 1;
        }
    }
    set_err("llx_session_update_lora_scale: lora not found");
    return 0;
}

extern "C" void llx_session_remove_lora(llx_session *sess, const char *lora_path)
{
    if (!sess || !sess->ctx || !lora_path || !*lora_path)
        return;
    for (size_t i = 0; i < sess->loras.size(); ++i)
    {
        if (sess->loras[i].path == lora_path)
        {
            if (sess->loras[i].ptr)
            {
                // 从上下文移除并释放
                llama_rm_adapter_lora(sess->ctx, sess->loras[i].ptr);
                llama_adapter_lora_free(sess->loras[i].ptr);
            }
            sess->loras.erase(sess->loras.begin() + i);
            apply_all_loras(sess);
            return;
        }
    }
}

extern "C" void llx_session_clear_lora(llx_session *sess)
{
    if (!sess || !sess->ctx)
        return;
    llama_clear_adapter_lora(sess->ctx);
    for (auto &e : sess->loras)
    {
        if (e.ptr) llama_adapter_lora_free(e.ptr);
    }
    sess->loras.clear();
    // 清理后清空 KV
    llama_memory_clear(llama_get_memory(sess->ctx), /*gain memory*/ true);
}

static void rebuild_sampler_from_request(llx_session *sess, const nlohmann::ordered_json &req)
{
    // 释放旧 sampler
    if (sess->sampler)
    {
        llama_sampler_free(sess->sampler);
        sess->sampler = nullptr;
    }
    auto schain = llama_sampler_chain_default_params();
    schain.no_perf = true;
    llama_sampler *sampler = llama_sampler_chain_init(schain);

    // 采样参数（默认与 OpenAI 接口相近）
    float temperature = req.value("temperature", 1.0f);
    float top_p = req.value("top_p", 1.0f);
    int top_k = req.value("top_k", 0);
    // greedy when temperature ~= 0
    if (temperature <= 0.0f)
    {
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    }
    else
    {
        // llama.cpp 的顺序一般是: penalties -> top_k -> top_p -> temp
        if (top_k > 0)
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(top_k));
        if (top_p < 1.0f)
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
        // 需要一个最终的随机采样器来选中 token
        uint32_t seed = 0;
        try {
            if (req.contains("seed")) seed = req["seed"].get<uint32_t>();
        } catch (...) {
            seed = 0;
        }
        if (seed == 0) {
            seed = (uint32_t)time(nullptr);
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));
    }
    sess->sampler = sampler;
}

extern "C" int llx_chat_complete_json(llx_session *sess,
                                       const char *request_json,
                                       char *out_json, size_t out_size)
{
    using json = nlohmann::ordered_json;
    if (!sess || !sess->ctx || !sess->chat || !request_json || !out_json || out_size == 0)
    {
        set_err("llx_chat_complete_json: invalid args");
        return 0;
    }

    json req;
    try
    {
        req = json::parse(request_json);
    }
    catch (...)
    {
        set_err("llx_chat_complete_json: parse request failed");
        return 0;
    }

    // 必需参数：messages（OpenAI chat 格式）
    if (!req.contains("messages"))
    {
        set_err("llx_chat_complete_json: missing messages");
        return 0;
    }

    // 工具与解析策略
    std::vector<common_chat_tool> tools;
    common_chat_tool_choice tool_choice = COMMON_CHAT_TOOL_CHOICE_AUTO;
    bool parallel_tool_calls = false;
    bool parse_tool_calls = true; // 启用输出解析
    try
    {
        if (req.contains("tools") && !req["tools"].is_null())
        {
            // 兼容输入把 parameters 写成字符串的情况：尝试转为 JSON 对象
            nlohmann::ordered_json tools_json = req["tools"].get<nlohmann::ordered_json>();
            if (tools_json.is_array())
            {
                for (auto &tool : tools_json)
                {
                    try
                    {
                        if (tool.contains("type") && tool["type"] == "function" && tool.contains("function"))
                        {
                            auto &fn = tool["function"];
                            if (fn.contains("parameters") && fn["parameters"].is_string())
                            {
                                auto parsed = nlohmann::ordered_json::parse(fn["parameters"].get<std::string>());
                                fn["parameters"] = parsed;
                            }
                        }
                    }
                    catch (...)
                    {
                        // 忽略单个 tool 的参数转换错误，留给下游抛错
                    }
                }
            }
            tools = common_chat_tools_parse_oaicompat(tools_json);
        }
        if (req.contains("tool_choice") && !req["tool_choice"].is_null())
            tool_choice = common_chat_tool_choice_parse_oaicompat(req["tool_choice"].get<std::string>());
        if (req.contains("parallel_tool_calls"))
            parallel_tool_calls = req["parallel_tool_calls"].get<bool>();
        if (req.contains("parse_tool_calls"))
            parse_tool_calls = req["parse_tool_calls"].get<bool>();
    }
    catch (const std::exception &e)
    {
        set_err(std::string("llx_chat_complete_json: tools/tool_choice parse failed: ") + e.what());
        return 0;
    }

    rebuild_sampler_from_request(sess, req);

    // 构造模板输入，应用并 prefill
    sess->cached.clear();
    sess->ncur = 0;

    std::vector<llama_token> toks;
    common_chat_params params;
    try
    {
        common_chat_templates_inputs inputs;
        inputs.add_generation_prompt = true;
        inputs.use_jinja = true;
        inputs.messages = common_chat_msgs_parse_oaicompat(req["messages"]);
        inputs.tools = tools;
        inputs.tool_choice = tool_choice;
        inputs.parallel_tool_calls = parallel_tool_calls;
        params = common_chat_templates_apply(sess->chat, inputs);
        // 启用解析 tool_calls（影响后续 common_chat_parse 的语法）
        params.format = params.format; // keep
        common_chat_syntax syntax;
        syntax.format = params.format;
        syntax.parse_tool_calls = parse_tool_calls;
        (void)syntax; // 仅用于 later parse

        toks = common_tokenize(sess->ctx, params.prompt, /*add_special*/ true, /*parse_special*/ true);
    }
    catch (const std::exception &e)
    {
        set_err(std::string("llx_chat_complete_json: messages/template apply failed: ") + e.what());
        return 0;
    }

    common_batch_clear(sess->batch);
    for (int i = 0; i < (int)toks.size(); ++i)
    {
        common_batch_add(sess->batch, toks[i], i, {0}, false);
    }
    sess->batch.logits[sess->batch.n_tokens - 1] = true;
    if (llama_decode(sess->ctx, sess->batch) != 0)
    {
        set_err("llx_chat_complete_json: prefill decode failed");
        return 0;
    }
    sess->ncur = sess->batch.n_tokens;

    // 生成循环
    int n_predict = req.value("max_tokens", 1024);
    int stop_token_emitted = 0;
    std::string generated;

    for (;;)
    {
        const auto *model = llama_get_model(sess->ctx);
        const auto *vocab = llama_model_get_vocab(model);
        llama_token new_id = llama_sampler_sample(sess->sampler, sess->ctx, -1);

        if (llama_vocab_is_eog(vocab, new_id) || sess->ncur - (int)toks.size() >= n_predict)
        {
            stop_token_emitted = llama_vocab_is_eog(vocab, new_id) ? 1 : 0;
            break;
        }

        std::string piece = common_token_to_piece(sess->ctx, new_id);
        sess->cached += piece;
        if (is_valid_utf8(sess->cached))
        {
            generated += sess->cached;
            sess->cached.clear();
        }

        common_batch_clear(sess->batch);
        common_batch_add(sess->batch, new_id, sess->ncur, {0}, true);
        sess->ncur += 1;
        if (llama_decode(sess->ctx, sess->batch) != 0)
        {
            break;
        }
    }

    // 解析生成文本，以便抽出 tool_calls（若启用）
    std::vector<common_chat_msg> out_msgs;
    common_chat_msg parsed;
    common_chat_syntax syntax;
    syntax.format = params.format;
    syntax.parse_tool_calls = parse_tool_calls;
    try
    {
        parsed = common_chat_parse(generated, /*is_partial=*/false, syntax);
    }
    catch (...)
    {
        // 忽略解析失败，作为普通 content 返回
        parsed.role = "assistant";
        parsed.content = generated;
    }

    // 构造 OpenAI 兼容响应
    json message;
    message["role"] = "assistant";
    if (!parsed.tool_calls.empty())
    {
        // 返回 tool_calls（函数名 + 参数字符串）
        json tcs = json::array();
        for (size_t i = 0; i < parsed.tool_calls.size(); ++i)
        {
            const auto &tc = parsed.tool_calls[i];
            json item;
            item["id"] = tc.id.empty() ? ("call_" + std::to_string(i)) : tc.id;
            item["type"] = "function";
            item["function"] = {
                {"name", tc.name},
                {"arguments", tc.arguments}
            };
            tcs.push_back(item);
        }
        message["tool_calls"] = tcs;
        message["content"] = nullptr;
    }
    else
    {
        message["content"] = parsed.content.empty() ? generated : parsed.content;
    }

    std::string finish_reason = "stop";
    if (sess->ncur - (int)toks.size() >= n_predict)
        finish_reason = "length";
    else if (!parsed.tool_calls.empty())
        finish_reason = "tool_calls";

    json choice;
    choice["index"] = 0;
    choice["message"] = message;
    choice["finish_reason"] = finish_reason;

    json resp;
    resp["object"] = "chat.completion";
    resp["model"] = req.value("model", "local-llm");
    resp["choices"] = json::array({choice});
    // usage 粗略估计：输入/输出 token 数
    int prompt_tokens = (int)toks.size();
    int completion_tokens = std::max(0, sess->ncur - prompt_tokens);
    resp["usage"] = {
        {"prompt_tokens", prompt_tokens},
        {"completion_tokens", completion_tokens},
        {"total_tokens", prompt_tokens + completion_tokens}
    };

    std::string s = resp.dump();
    size_t n = std::min(out_size - 1, s.size());
    memcpy(out_json, s.data(), n);
    out_json[n] = '\0';
    return 1;
}

extern "C" void llx_session_free(llx_session *sess)
{
    if (!sess)
        return;
    if (sess->sampler)
        llama_sampler_free(sess->sampler);
    if (sess->chat)
        common_chat_templates_free(sess->chat);
    if (!sess->loras.empty())
    {
        llama_clear_adapter_lora(sess->ctx);
        for (auto &e : sess->loras)
        {
            if (e.ptr) llama_adapter_lora_free(e.ptr);
        }
        sess->loras.clear();
    }
    if (sess->ctx)
        llama_free(sess->ctx);
    if (sess->batch.token || sess->batch.embd || sess->batch.pos)
        llama_batch_free(sess->batch);
    delete sess;
}

extern "C" void llx_session_kv_clear(llx_session *sess)
{
    if (!sess || !sess->ctx)
        return;
    llama_memory_clear(llama_get_memory(sess->ctx), /*gain memory*/ true);
}

static bool is_valid_utf8(const std::string &s)
{
    const unsigned char *bytes = (const unsigned char *)s.c_str();
    int num = 0;
    while (*bytes)
    {
        if ((*bytes & 0x80) == 0x00)
            num = 1;
        else if ((*bytes & 0xE0) == 0xC0)
            num = 2;
        else if ((*bytes & 0xF0) == 0xE0)
            num = 3;
        else if ((*bytes & 0xF8) == 0xF0)
            num = 4;
        else
            return false;
        bytes++;
        for (int i = 1; i < num; ++i)
        {
            if ((*bytes & 0xC0) != 0x80)
                return false;
            bytes++;
        }
    }
    return true;
}

extern "C" int llx_session_init_from_messages_json(llx_session *sess, const char *messages_json, int n_len)
{
    if (!sess || !sess->ctx || !sess->chat || !messages_json)
    {
        set_err("llx_session_init_from_messages_json: invalid args");
        return 0;
    }

    sess->cached.clear();
    sess->ncur = 0;

    std::vector<llama_token> toks;
    try
    {
        common_chat_templates_inputs inputs;
        inputs.add_generation_prompt = true;
        inputs.use_jinja = true;
        inputs.messages = common_chat_msgs_parse_oaicompat(std::string(messages_json));
        auto params = common_chat_templates_apply(sess->chat, inputs);
        toks = common_tokenize(sess->ctx, params.prompt, /*add_special*/ true, /*parse_special*/ true);
    }
    catch (...)
    {
        set_err("llx_session_init_from_messages_json: parse/apply failed");
        return 0;
    }

    common_batch_clear(sess->batch);
    for (int i = 0; i < (int)toks.size(); ++i)
    {
        common_batch_add(sess->batch, toks[i], i, {0}, false);
    }
    sess->batch.logits[sess->batch.n_tokens - 1] = true;

    if (llama_decode(sess->ctx, sess->batch) != 0)
    {
        set_err("llama_decode failed");
        return 0;
    }

    sess->ncur = sess->batch.n_tokens;
    (void)n_len; // 仅用来估算 kv 需求，不强制中断
    return sess->ncur;
}

extern "C" int llx_session_init_from_text(llx_session *sess, const char *text, int format_chat, int n_len)
{
    if (!sess || !sess->ctx || !text)
    {
        set_err("llx_session_init_from_text: invalid args");
        return 0;
    }

    sess->cached.clear();
    sess->ncur = 0;

    std::vector<llama_token> toks;
    if (format_chat && sess->chat)
    {
        common_chat_templates_inputs inputs;
        inputs.add_generation_prompt = true;
        inputs.use_jinja = true;
        common_chat_msg u;
        u.role = "user";
        u.content = text;
        inputs.messages.push_back(u);
        auto params = common_chat_templates_apply(sess->chat, inputs);
        toks = common_tokenize(sess->ctx, params.prompt, true, true);
    }
    else
    {
        toks = common_tokenize(sess->ctx, text, true, format_chat != 0);
    }

    common_batch_clear(sess->batch);
    for (int i = 0; i < (int)toks.size(); ++i)
    {
        common_batch_add(sess->batch, toks[i], i, {0}, false);
    }
    sess->batch.logits[sess->batch.n_tokens - 1] = true;

    if (llama_decode(sess->ctx, sess->batch) != 0)
    {
        set_err("llama_decode failed");
        return 0;
    }

    sess->ncur = sess->batch.n_tokens;
    (void)n_len;
    return sess->ncur;
}

extern "C" int llx_session_step(llx_session *sess, int n_len,
                                char *out_utf8, size_t out_size,
                                int *finished)
{
    if (!sess || !sess->ctx || !sess->sampler || !out_utf8 || out_size == 0 || !finished)
    {
        set_err("llx_session_step: invalid args");
        return 0;
    }
    *finished = 0;
    out_utf8[0] = '\0';

    const auto *model = llama_get_model(sess->ctx);
    const auto *vocab = llama_model_get_vocab(model);

    llama_token new_id = llama_sampler_sample(sess->sampler, sess->ctx, -1);

    if (llama_vocab_is_eog(vocab, new_id) || sess->ncur >= n_len)
    {
        *finished = 1;
        return 1;
    }

    std::string piece = common_token_to_piece(sess->ctx, new_id);
    sess->cached += piece;

    if (is_valid_utf8(sess->cached))
    {
        // flush
        size_t ncopy = std::min(out_size - 1, sess->cached.size());
        memcpy(out_utf8, sess->cached.data(), ncopy);
        out_utf8[ncopy] = '\0';
        sess->cached.clear();
    }
    else
    {
        // incomplete utf8 -> emit empty
        out_utf8[0] = '\0';
    }

    common_batch_clear(sess->batch);
    common_batch_add(sess->batch, new_id, sess->ncur, {0}, true);
    sess->ncur += 1;

    if (llama_decode(sess->ctx, sess->batch) != 0)
    {
        *finished = 1;
    }
    return 1;
}

extern "C" int llx_bench(llx_session *sess, int pp, int tg, int pl, int nr,
                         char *out, size_t out_size)
{
    if (!sess || !sess->ctx || !sess->model || !out || out_size == 0)
    {
        set_err("llx_bench: invalid args");
        return 0;
    }

    double pp_avg = 0, tg_avg = 0, pp_std = 0, tg_std = 0;

    llama_context *ctx = sess->ctx;
    llama_model *m = sess->model;
    llama_batch *b = &sess->batch;

    for (int ri = 0; ri < nr; ++ri)
    {
        common_batch_clear(*b);
        for (int i = 0; i < pp; ++i)
        {
            common_batch_add(*b, 0, i, {0}, false);
        }
        b->logits[b->n_tokens - 1] = true;
        llama_memory_clear(llama_get_memory(ctx), false);

        auto t0 = ggml_time_us();
        llama_decode(ctx, *b);
        auto t1 = ggml_time_us();

        llama_memory_clear(llama_get_memory(ctx), false);
        auto g0 = ggml_time_us();
        for (int i = 0; i < tg; ++i)
        {
            common_batch_clear(*b);
            for (int j = 0; j < pl; ++j)
                common_batch_add(*b, 0, i, {j}, true);
            llama_decode(ctx, *b);
        }
        auto g1 = ggml_time_us();

        double t_pp = (t1 - t0) / 1e6;
        double t_tg = (g1 - g0) / 1e6;
        double s_pp = pp / std::max(1e-9, t_pp);
        double s_tg = (pl * tg) / std::max(1e-9, t_tg);

        pp_avg += s_pp;
        tg_avg += s_tg;
        pp_std += s_pp * s_pp;
        tg_std += s_tg * s_tg;
    }

    pp_avg /= std::max(1, nr);
    tg_avg /= std::max(1, nr);
    if (nr > 1)
    {
        pp_std = sqrt(pp_std / (nr - 1) - pp_avg * pp_avg * nr / (nr - 1.0));
        tg_std = sqrt(tg_std / (nr - 1) - tg_avg * tg_avg * nr / (nr - 1.0));
    }
    else
    {
        pp_std = tg_std = 0.0;
    }

    char desc[128];
    llama_model_desc(m, desc, sizeof(desc));
    double size_gb = llama_model_size(m) / (1024.0 * 1024.0 * 1024.0);
    double nparam = llama_model_n_params(m) / 1e9;

    std::ostringstream os;
    os.setf(std::ios::fixed);
    os.precision(2);
    os << "| model | size | params | backend | test | t/s |\n"
       << "| --- | --- | --- | --- | --- | --- |\n"
       << "| " << desc << " | " << size_gb << "GiB | " << nparam << "B | macOS | pp " << pp
       << " | " << pp_avg << " ± " << pp_std << " |\n"
       << "| " << desc << " | " << size_gb << "GiB | " << nparam << "B | macOS | tg " << tg
       << " | " << tg_avg << " ± " << tg_std << " |\n";

    std::string s = os.str();
    size_t n = std::min(out_size - 1, s.size());
    memcpy(out, s.data(), n);
    out[n] = '\0';
    return 1;
}
