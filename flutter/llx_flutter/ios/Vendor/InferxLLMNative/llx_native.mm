#import <Foundation/Foundation.h>
#include <TargetConditionals.h>
#include <string>
#include <vector>
#include <sstream>
#include <algorithm>
#include <unistd.h>

#include <llama/llama.h>

#include "llx.h"

static thread_local std::string g_err;
static void set_err(const std::string &e) { g_err = e; }
extern "C" const char *llx_last_error(void) { return g_err.empty() ? "" : g_err.c_str(); }

struct llx_model { llama_model *m = nullptr; };

struct llx_session {
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
    llama_batch batch{};
    llama_sampler *sampler = nullptr;
    const llama_vocab *vocab = nullptr;
    std::string cached;
    int ncur = 0;
    int n_ctx = 8192;
    struct lora_entry { std::string path; llama_adapter_lora *ptr = nullptr; float scale = 1.0f; };
    std::vector<lora_entry> loras;
};

// ===== Template detection helpers =====
enum llx_template_kind { LLX_TPL_LLAMa3 = 0, LLX_TPL_CHATML = 1, LLX_TPL_PLAIN = 2 };

static bool vocab_supports_control_token(const llama_vocab *vocab, const char *tok_text) {
    if (!vocab || !tok_text) return false;
    // tokenize special token string with parse_special=true
    std::string s(tok_text);
    std::vector<llama_token> tmp; tmp.resize((int)s.size() + 2);
    int n = llama_tokenize(vocab, s.c_str(), (int)s.size(), tmp.data(), (int)tmp.size(), /*add_bos*/ false, /*parse_special*/ true);
    if (n <= 0) return false;
    llama_token t0 = tmp[0];
    return llama_vocab_is_control(vocab, t0) != 0;
}

static llx_template_kind detect_template_kind(const llama_vocab *vocab) {
    // Prefer Llama-3 style if supported; else ChatML; else Plain
    if (vocab_supports_control_token(vocab, "<|start_header_id|>") && vocab_supports_control_token(vocab, "<|eot_id|>")) {
        return LLX_TPL_LLAMa3;
    }
    if (vocab_supports_control_token(vocab, "<|im_start|>") && vocab_supports_control_token(vocab, "<|im_end|>")) {
        return LLX_TPL_CHATML;
    }
    return LLX_TPL_PLAIN;
}

static int detect_threads() {
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    if (n < 1) n = 1;
    int t = (int)n - 2;
    if (t < 1) t = 1;
    if (t > 8) t = 8;
    return t;
}

extern "C" void llx_backend_init(void) { llama_backend_init(); }
extern "C" void llx_backend_free(void) { llama_backend_free(); }
extern "C" const char *llx_system_info(void) { return llama_print_system_info(); }

extern "C" int llx_model_load(const char *path, llx_model **out_model) {
    if (!path || !out_model) { set_err("llx_model_load: invalid args"); return 0; }
    *out_model = nullptr;

    llama_model_params mp = llama_model_default_params();
#if TARGET_OS_SIMULATOR
    mp.n_gpu_layers = 0; // simulator: force CPU
#endif
    llama_model *m = llama_model_load_from_file(path, mp);
    if (!m) { set_err("llx_model_load: llama_model_load_from_file failed"); return 0; }
    auto *wrap = new llx_model();
    wrap->m = m;
    *out_model = wrap;
    return 1;
}

extern "C" void llx_model_free(llx_model *model) {
    if (!model) return;
    if (model->m) llama_model_free(model->m);
    delete model;
}

extern "C" llx_session_params llx_session_default_params(void) {
    llx_session_params p; p.n_ctx = 8192; p.n_threads = 0; return p;
}

extern "C" int llx_session_create(llx_model *model, llx_session_params params, llx_session **out_sess) {
    if (!model || !model->m || !out_sess) { set_err("llx_session_create: invalid args"); return 0; }
    *out_sess = nullptr;

    int n_threads = params.n_threads <= 0 ? detect_threads() : params.n_threads;
    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = params.n_ctx > 0 ? params.n_ctx : 8192;
    cp.n_threads = n_threads;
    cp.n_threads_batch = n_threads;

    llama_context *ctx = llama_init_from_model(model->m, cp);
    if (!ctx) { set_err("llx_session_create: llama_init_from_model failed"); return 0; }

    llama_batch batch = llama_batch_init(cp.n_ctx, 0, 1);
    auto schain = llama_sampler_chain_default_params();
    schain.no_perf = true;
    llama_sampler *sampler = llama_sampler_chain_init(schain);
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

    auto *s = new llx_session();
    s->model = model->m;
    s->ctx = ctx;
    s->batch = batch;
    s->sampler = sampler;
    s->vocab = llama_model_get_vocab(model->m);
    s->n_ctx = cp.n_ctx;
    *out_sess = s;
    return 1;
}

extern "C" void llx_session_free(llx_session *sess) {
    if (!sess) return;
    if (sess->sampler) llama_sampler_free(sess->sampler);
    if (sess->ctx) llama_free(sess->ctx);
    if (sess->batch.token || sess->batch.embd || sess->batch.pos) llama_batch_free(sess->batch);
    delete sess;
}

extern "C" void llx_session_kv_clear(llx_session *sess) {
    if (!sess || !sess->ctx) return;
    llama_memory_clear(llama_get_memory(sess->ctx), /*gain memory*/ true);
}

// ===== LoRA (full support mirroring core/Android) =====
static int apply_all_loras(llx_session *sess) {
    if (!sess || !sess->ctx) return 0;
    llama_clear_adapter_lora(sess->ctx);
    for (auto &e : sess->loras) {
        if (e.ptr) {
            if (llama_set_adapter_lora(sess->ctx, e.ptr, e.scale) < 0) {
                set_err("apply_all_loras: llama_set_adapter_lora failed");
                return 0;
            }
        }
    }
    llama_memory_clear(llama_get_memory(sess->ctx), /*gain memory*/ true);
    return 1;
}

extern "C" int llx_session_load_lora(llx_session *sess, const char *lora_path, float scale) {
    if (!sess || !sess->ctx || !sess->model || !lora_path || !*lora_path) { set_err("llx_session_load_lora: invalid args"); return 0; }
    // clear
    if (!sess->loras.empty()) {
        llama_clear_adapter_lora(sess->ctx);
        for (auto &e : sess->loras) { if (e.ptr) llama_adapter_lora_free(e.ptr); }
        sess->loras.clear();
    }
    // load and set
    llama_adapter_lora *adapter = llama_adapter_lora_init(sess->model, lora_path);
    if (!adapter) { set_err("llx_session_load_lora: llama_adapter_lora_init failed"); return 0; }
    if (scale <= 0.0f) scale = 1.0f;
    if (llama_set_adapter_lora(sess->ctx, adapter, scale) < 0) {
        llama_adapter_lora_free(adapter); set_err("llx_session_load_lora: llama_set_adapter_lora failed"); return 0;
    }
    llx_session::lora_entry ent; ent.path = lora_path; ent.ptr = adapter; ent.scale = scale; sess->loras.push_back(ent);
    llama_memory_clear(llama_get_memory(sess->ctx), /*gain memory*/ true);
    return 1;
}

extern "C" int llx_session_add_lora(llx_session *sess, const char *lora_path, float scale) {
    if (!sess || !sess->ctx || !sess->model || !lora_path || !*lora_path) { set_err("llx_session_add_lora: invalid args"); return 0; }
    if (scale <= 0.0f) scale = 1.0f;
    for (auto &e : sess->loras) {
        if (e.path == lora_path) { e.scale = scale; return apply_all_loras(sess); }
    }
    llama_adapter_lora *adapter = llama_adapter_lora_init(sess->model, lora_path);
    if (!adapter) { set_err("llx_session_add_lora: llama_adapter_lora_init failed"); return 0; }
    llx_session::lora_entry ent; ent.path = lora_path; ent.ptr = adapter; ent.scale = scale; sess->loras.push_back(ent);
    return apply_all_loras(sess);
}

extern "C" int llx_session_update_lora_scale(llx_session *sess, const char *lora_path, float scale) {
    if (!sess || !sess->ctx || !lora_path || !*lora_path) { set_err("llx_session_update_lora_scale: invalid args"); return 0; }
    if (scale <= 0.0f) scale = 1.0f;
    for (auto &e : sess->loras) {
        if (e.path == lora_path) { e.scale = scale; return apply_all_loras(sess); }
    }
    set_err("llx_session_update_lora_scale: lora not found");
    return 0;
}

extern "C" void llx_session_remove_lora(llx_session *sess, const char *lora_path) {
    if (!sess || !sess->ctx || !lora_path || !*lora_path) return;
    for (size_t i = 0; i < sess->loras.size(); ++i) {
        if (sess->loras[i].path == lora_path) {
            if (sess->loras[i].ptr) {
                llama_rm_adapter_lora(sess->ctx, sess->loras[i].ptr);
                llama_adapter_lora_free(sess->loras[i].ptr);
            }
            sess->loras.erase(sess->loras.begin() + i);
            (void)apply_all_loras(sess);
            return;
        }
    }
}

extern "C" void llx_session_clear_lora(llx_session *sess) {
    if (!sess || !sess->ctx) return;
    llama_clear_adapter_lora(sess->ctx);
    for (auto &e : sess->loras) { if (e.ptr) llama_adapter_lora_free(e.ptr); }
    sess->loras.clear();
    llama_memory_clear(llama_get_memory(sess->ctx), /*gain memory*/ true);
}

static bool is_valid_utf8(const std::string &s) {
    const unsigned char *bytes = (const unsigned char *)s.c_str();
    int num = 0;
    while (*bytes) {
        if ((*bytes & 0x80) == 0x00) num = 1;
        else if ((*bytes & 0xE0) == 0xC0) num = 2;
        else if ((*bytes & 0xF0) == 0xE0) num = 3;
        else if ((*bytes & 0xF8) == 0xF0) num = 4;
        else return false;
        bytes++;
        for (int i = 1; i < num; ++i) {
            if ((*bytes & 0xC0) != 0x80) return false;
            bytes++;
        }
    }
    return true;
}

// llama_batch helpers (avoid relying on common.*)
static inline void llx_batch_clear(llama_batch &batch) {
    batch.n_tokens = 0;
}
static inline void llx_batch_add(llama_batch &batch, llama_token id, int32_t pos, std::initializer_list<int32_t> seq_ids, bool logits) {
    batch.token   [batch.n_tokens] = id;
    batch.pos     [batch.n_tokens] = pos;
    batch.n_seq_id[batch.n_tokens] = (int32_t)seq_ids.size();
    int i = 0; for (auto v : seq_ids) { batch.seq_id[batch.n_tokens][i++] = v; }
    batch.logits  [batch.n_tokens] = logits ? 1 : 0;
    batch.n_tokens += 1;
}

static std::vector<llama_token> tokenize(llx_session *sess, const std::string &text, bool add_bos, bool parse_special) {
    std::vector<llama_token> out;
    if (!sess || !sess->vocab) return out;
    const int approx = (int)text.size() + (add_bos ? 2 : 1);
    out.resize(approx);
    int n = llama_tokenize(sess->vocab, text.c_str(), (int)text.size(), out.data(), (int)out.size(), add_bos, parse_special);
    if (n < 0) {
        out.resize(-n);
        n = llama_tokenize(sess->vocab, text.c_str(), (int)text.size(), out.data(), (int)out.size(), add_bos, parse_special);
    }
    if (n < 0) n = 0;
    out.resize(n);
    return out;
}

extern "C" int llx_session_init_from_text(llx_session *sess, const char *text, int format_chat, int n_len) {
    if (!sess || !sess->ctx || !text) { set_err("llx_session_init_from_text: invalid args"); return 0; }
    (void)n_len;
    sess->cached.clear();
    sess->ncur = 0;

    std::string prompt;
    if (format_chat) {
        auto kind = detect_template_kind(sess->vocab);
        if (kind == LLX_TPL_LLAMa3) {
            // Llama-3
            prompt.reserve(strlen(text) + 128);
            prompt += "<|start_header_id|>user<|end_header_id|>\n\n";
            prompt += text;
            prompt += "<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n";
        } else if (kind == LLX_TPL_CHATML) {
            // ChatML (Qwen)
            prompt.reserve(strlen(text) + 64);
            prompt += "<|im_start|>user\n";
            prompt += text;
            prompt += "<|im_end|><|im_start|>assistant\n"; // no end to start generation
        } else {
            // Plain fallback
            prompt.reserve(strlen(text) + 32);
            prompt += "User: ";
            prompt += text;
            prompt += "\nAssistant: ";
        }
    } else {
        prompt = text;
    }

    auto toks = tokenize(sess, prompt, /*add_bos*/ true, /*parse_special*/ true);
    llama_batch b = sess->batch;
    llx_batch_clear(b);
    for (int i = 0; i < (int)toks.size(); ++i) {
        llx_batch_add(b, toks[i], i, {0}, false);
    }
    b.logits[b.n_tokens - 1] = true;
    if (llama_decode(sess->ctx, b) != 0) { set_err("llx_session_init_from_text: llama_decode failed"); return 0; }
    sess->batch = b;
    sess->ncur = b.n_tokens;
    return sess->ncur;
}

extern "C" int llx_session_init_from_messages_json(llx_session *sess, const char *messages_json, int n_len) {
    if (!sess || !sess->ctx || !messages_json) { set_err("llx_session_init_from_messages_json: invalid args"); return 0; }
    (void)n_len;
    // Simple parser with Foundation
    @autoreleasepool {
        NSData *data = [NSData dataWithBytes:messages_json length:strlen(messages_json)];
        NSError *err = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (err || ![obj isKindOfClass:[NSArray class]]) {
            set_err("llx_session_init_from_messages_json: parse failed");
            return 0;
        }
        NSArray *arr = (NSArray *)obj;
        NSMutableString *prompt = [NSMutableString string];
        auto kind = detect_template_kind(sess->vocab);
        for (id it in arr) {
            if (![it isKindOfClass:[NSDictionary class]]) continue;
            NSString *role = ((NSDictionary *)it)[@"role"] ?: @"";
            NSString *content = ((NSDictionary *)it)[@"content"] ?: @"";
            if (kind == LLX_TPL_LLAMa3) {
                if ([role isEqualToString:@"system"]) {
                    [prompt appendString:@"<|start_header_id|>system<|end_header_id|>\n\n"]; [prompt appendString:content]; [prompt appendString:@"<|eot_id|>"];
                } else if ([role isEqualToString:@"assistant"]) {
                    [prompt appendString:@"<|start_header_id|>assistant<|end_header_id|>\n\n"]; [prompt appendString:content]; [prompt appendString:@"<|eot_id|>"];
                } else {
                    [prompt appendString:@"<|start_header_id|>user<|end_header_id|>\n\n"]; [prompt appendString:content]; [prompt appendString:@"<|eot_id|>"];
                }
            } else if (kind == LLX_TPL_CHATML) {
                // ChatML: <|im_start|>role\ncontent<|im_end|>
                NSString *roleOut = ([role length] ? role : @"user");
                [prompt appendString:@"<|im_start|>"]; [prompt appendString:roleOut]; [prompt appendString:@"\n"]; [prompt appendString:content]; [prompt appendString:@"<|im_end|>"];
            } else {
                // Plain fallback
                NSString *roleOut = ([role length] ? role : @"user");
                [prompt appendString:roleOut]; [prompt appendString:@": "]; [prompt appendString:content]; [prompt appendString:@"\n"];            
            }
        }
        // 追加 assistant 起始以触发生成
        if (kind == LLX_TPL_LLAMa3) {
            [prompt appendString:@"<|start_header_id|>assistant<|end_header_id|>\n\n"];
        } else if (kind == LLX_TPL_CHATML) {
            [prompt appendString:@"<|im_start|>assistant\n"];
        } else {
            [prompt appendString:@"Assistant: "];
        }
        std::string p([prompt UTF8String]);
        return llx_session_init_from_text(sess, p.c_str(), /*format_chat*/ 0, n_len);
    }
}

extern "C" int llx_session_step(llx_session *sess, int n_len, char *out_utf8, size_t out_size, int *finished) {
    if (!sess || !sess->ctx || !sess->sampler || !out_utf8 || out_size == 0 || !finished) {
        set_err("llx_session_step: invalid args"); return 0;
    }
    *finished = 0; out_utf8[0] = '\0';

    llama_token new_id = llama_sampler_sample(sess->sampler, sess->ctx, -1);
    if (llama_vocab_is_eog(sess->vocab, new_id) || sess->ncur >= n_len) { *finished = 1; return 1; }

    // token -> piece string（过滤控制 token 不输出）
    if (!llama_vocab_is_control(sess->vocab, new_id)) {
        std::string piece;
        {
            int n = llama_token_to_piece(sess->vocab, new_id, nullptr, 0, 0, false);
            if (n < 0) n = -n;
            std::string tmp; tmp.resize(n);
            int n2 = llama_token_to_piece(sess->vocab, new_id, &tmp[0], n, 0, false);
            if (n2 < 0) n2 = -n2;
            tmp.resize(n2);
            piece.swap(tmp);
        }
        sess->cached += piece;
        if (is_valid_utf8(sess->cached)) {
            size_t ncopy = std::min(out_size - 1, sess->cached.size());
            memcpy(out_utf8, sess->cached.data(), ncopy);
            out_utf8[ncopy] = '\0';
            sess->cached.clear();
        } else {
            out_utf8[0] = '\0';
        }
    } else {
        // 控制 token：不修改 cached，不输出片段
        out_utf8[0] = '\0';
    }

    llama_batch b = sess->batch;
    llx_batch_clear(b);
    llx_batch_add(b, new_id, sess->ncur, {0}, true);
    sess->ncur += 1;
    if (llama_decode(sess->ctx, b) != 0) { *finished = 1; }
    sess->batch = b;
    return 1;
}

extern "C" int llx_bench(llx_session *sess, int pp, int tg, int pl, int nr, char *out, size_t out_size) {
    if (!sess || !sess->ctx || !sess->model || !out || out_size == 0) { set_err("llx_bench: invalid args"); return 0; }
    double pp_avg = 0, tg_avg = 0, pp_std = 0, tg_std = 0;
    llama_context *ctx = sess->ctx; llama_model *m = sess->model; llama_batch *b = &sess->batch;
    for (int ri = 0; ri < nr; ++ri) {
    llx_batch_clear(*b);
    for (int i = 0; i < pp; ++i) llx_batch_add(*b, 0, i, {0}, false);
        b->logits[b->n_tokens - 1] = true;
        llama_memory_clear(llama_get_memory(ctx), false);
        auto t0 = ggml_time_us(); llama_decode(ctx, *b); auto t1 = ggml_time_us();
        llama_memory_clear(llama_get_memory(ctx), false);
        auto g0 = ggml_time_us();
        for (int i = 0; i < tg; ++i) {
        llx_batch_clear(*b);
        for (int j = 0; j < pl; ++j) llx_batch_add(*b, 0, i, {j}, true);
            llama_decode(ctx, *b);
        }
        auto g1 = ggml_time_us();
        double t_pp = (t1 - t0) / 1e6; double t_tg = (g1 - g0) / 1e6;
        double s_pp = pp / std::max(1e-9, t_pp); double s_tg = (pl * tg) / std::max(1e-9, t_tg);
        pp_avg += s_pp; tg_avg += s_tg; pp_std += s_pp * s_pp; tg_std += s_tg * s_tg;
    }
    pp_avg /= std::max(1, nr); tg_avg /= std::max(1, nr);
    if (nr > 1) { pp_std = sqrt(pp_std / (nr - 1) - pp_avg * pp_avg * nr / (nr - 1.0)); tg_std = sqrt(tg_std / (nr - 1) - tg_avg * tg_avg * nr / (nr - 1.0)); }
    else { pp_std = tg_std = 0.0; }
    char desc[128]; llama_model_desc(m, desc, sizeof(desc));
    double size_gb = llama_model_size(m) / (1024.0 * 1024.0 * 1024.0); double nparam = llama_model_n_params(m) / 1e9;
    std::ostringstream os; os.setf(std::ios::fixed); os.precision(2);
    os << "| model | size | params | backend | test | t/s |\n"
       << "| --- | --- | --- | --- | --- | --- |\n"
       << "| " << desc << " | " << size_gb << "GiB | " << nparam << "B | iOS | pp " << pp
       << " | " << pp_avg << " ± " << pp_std << " |\n"
       << "| " << desc << " | " << size_gb << "GiB | " << nparam << "B | iOS | tg " << tg
       << " | " << tg_avg << " ± " << tg_std << " |\n";
    std::string s = os.str(); size_t n = std::min(out_size - 1, s.size()); memcpy(out, s.data(), n); out[n] = '\0';
    return 1;
}

extern "C" int llx_chat_complete_json(llx_session *sess, const char *request_json, char *out_json, size_t out_size) {
    if (!sess || !sess->ctx || !request_json || !out_json || out_size == 0) { set_err("llx_chat_complete_json: invalid args"); return 0; }
    @autoreleasepool {
        NSData *data = [NSData dataWithBytes:request_json length:strlen(request_json)];
        NSError *err = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (err || ![obj isKindOfClass:[NSDictionary class]]) { set_err("llx_chat_complete_json: parse request failed"); return 0; }
        NSDictionary *req = (NSDictionary *)obj;
        NSArray *messages = req[@"messages"];
        if (![messages isKindOfClass:[NSArray class]]) { set_err("llx_chat_complete_json: missing messages"); return 0; }

        // build prompt according to detected template
        NSMutableString *prompt = [NSMutableString string];
        auto kind = detect_template_kind(sess->vocab);
        for (id it in messages) {
            if (![it isKindOfClass:[NSDictionary class]]) continue;
            NSString *role = ((NSDictionary *)it)[@"role"] ?: @"";
            NSString *content = ((NSDictionary *)it)[@"content"] ?: @"";
            if (kind == LLX_TPL_LLAMa3) {
                if ([role isEqualToString:@"system"]) {
                    [prompt appendString:@"<|start_header_id|>system<|end_header_id|>\n\n"]; [prompt appendString:content]; [prompt appendString:@"<|eot_id|>"];
                } else if ([role isEqualToString:@"assistant"]) {
                    [prompt appendString:@"<|start_header_id|>assistant<|end_header_id|>\n\n"]; [prompt appendString:content]; [prompt appendString:@"<|eot_id|>"];
                } else {
                    [prompt appendString:@"<|start_header_id|>user<|end_header_id|>\n\n"]; [prompt appendString:content]; [prompt appendString:@"<|eot_id|>"];
                }
            } else if (kind == LLX_TPL_CHATML) {
                NSString *roleOut = ([role length] ? role : @"user");
                [prompt appendString:@"<|im_start|>"]; [prompt appendString:roleOut]; [prompt appendString:@"\n"]; [prompt appendString:content]; [prompt appendString:@"<|im_end|>"];
            } else {
                NSString *roleOut = ([role length] ? role : @"user");
                [prompt appendString:roleOut]; [prompt appendString:@": "]; [prompt appendString:content]; [prompt appendString:@"\n"];            
            }
        }
        if (kind == LLX_TPL_LLAMa3) {
            [prompt appendString:@"<|start_header_id|>assistant<|end_header_id|>\n\n"];
        } else if (kind == LLX_TPL_CHATML) {
            [prompt appendString:@"<|im_start|>assistant\n"];
        } else {
            [prompt appendString:@"Assistant: "];
        }

        // sampler params
        float temperature = req[@"temperature"] ? [req[@"temperature"] floatValue] : 1.0f;
        float top_p = req[@"top_p"] ? [req[@"top_p"] floatValue] : 1.0f;
        int top_k = req[@"top_k"] ? [req[@"top_k"] intValue] : 0;
        int n_predict = req[@"max_tokens"] ? [req[@"max_tokens"] intValue] : 256;

        if (sess->sampler) { llama_sampler_free(sess->sampler); sess->sampler = nullptr; }
        auto schain = llama_sampler_chain_default_params(); schain.no_perf = true; llama_sampler *sampler = llama_sampler_chain_init(schain);
        if (temperature <= 0.0f) {
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
        } else {
            if (top_k > 0) llama_sampler_chain_add(sampler, llama_sampler_init_top_k(top_k));
            if (top_p < 1.0f) llama_sampler_chain_add(sampler, llama_sampler_init_top_p(top_p, 1));
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
            uint32_t seed = (uint32_t)time(nullptr);
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));
        }
        sess->sampler = sampler;

        // prefill
        std::string p([prompt UTF8String]);
        sess->cached.clear(); sess->ncur = 0;
        auto toks = tokenize(sess, p, true, true);
        llx_batch_clear(sess->batch);
        for (int i = 0; i < (int)toks.size(); ++i) llx_batch_add(sess->batch, toks[i], i, {0}, false);
        sess->batch.logits[sess->batch.n_tokens - 1] = true;
        if (llama_decode(sess->ctx, sess->batch) != 0) { set_err("llx_chat_complete_json: prefill decode failed"); return 0; }
        sess->ncur = sess->batch.n_tokens;

        // generate loop
        std::string generated;
        int stop_token_emitted = 0;
        while (true) {
            llama_token new_id = llama_sampler_sample(sess->sampler, sess->ctx, -1);
            if (llama_vocab_is_eog(sess->vocab, new_id) || sess->ncur - (int)toks.size() >= n_predict) {
                stop_token_emitted = llama_vocab_is_eog(sess->vocab, new_id) ? 1 : 0; break;
            }
            if (!llama_vocab_is_control(sess->vocab, new_id)) {
                std::string piece; {
                    int n = llama_token_to_piece(sess->vocab, new_id, nullptr, 0, 0, false);
                    if (n < 0) n = -n; std::string tmp; tmp.resize(n);
                    int n2 = llama_token_to_piece(sess->vocab, new_id, &tmp[0], n, 0, false);
                    if (n2 < 0) n2 = -n2; tmp.resize(n2); piece.swap(tmp);
                }
                sess->cached += piece;
                if (is_valid_utf8(sess->cached)) { generated += sess->cached; sess->cached.clear(); }
            }
            llx_batch_clear(sess->batch);
            llx_batch_add(sess->batch, new_id, sess->ncur, {0}, true);
            sess->ncur += 1;
            if (llama_decode(sess->ctx, sess->batch) != 0) { break; }
        }

        // response JSON (OpenAI-like)
        std::ostringstream os;
        std::string modelName = "local-llm";
        if ([req[@"model"] isKindOfClass:[NSString class]]) { modelName = std::string([(NSString*)req[@"model"] UTF8String]); }
        int prompt_tokens = (int)toks.size(); int completion_tokens = std::max(0, sess->ncur - prompt_tokens);
        std::string finish_reason = (sess->ncur - (int)toks.size() >= n_predict) ? "length" : (stop_token_emitted ? "stop" : "stop");
        auto esc = [](const std::string &s)->std::string { std::string r; r.reserve(s.size()+8); for(char c: s){ if(c=='"') r += "\\\""; else if(c=='\\') r += "\\\\"; else if(c=='\n') r += "\\n"; else r += c; } return r; };
        os << "{\"object\":\"chat.completion\",\"model\":\"" << esc(modelName) << "\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"" << esc(generated) << "\"},\"finish_reason\":\"" << finish_reason << "\"}],\"usage\":{\"prompt_tokens\":" << prompt_tokens << ",\"completion_tokens\":" << completion_tokens << ",\"total_tokens\":" << (prompt_tokens+completion_tokens) << "}}";
        std::string s = os.str(); size_t n = std::min(out_size - 1, s.size()); memcpy(out_json, s.data(), n); out_json[n] = '\0';
        return 1;
    }
}


