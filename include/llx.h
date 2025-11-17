#pragma once
#ifdef __cplusplus
extern "C"
{
#endif

#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#ifdef LLX_BUILD_DLL
#define LLX_API __declspec(dllexport)
#else
#define LLX_API __declspec(dllimport)
#endif
#else
#define LLX_API __attribute__((visibility("default")))
#endif

    // 不透明句柄
    typedef struct llx_model llx_model;
    typedef struct llx_session llx_session;

    typedef struct
    {
        int n_ctx;     // 默认 8192
        int n_threads; // <=0 自动探测 (<=8)
    } llx_session_params;

    LLX_API void llx_backend_init(void);
    LLX_API void llx_backend_free(void);
    LLX_API const char *llx_system_info(void);

    // 线程本地错误字符串（返回指针在下一次 LLX 调用前有效）
    LLX_API const char *llx_last_error(void);

    // model
    LLX_API int llx_model_load(const char *path, llx_model **out_model);
    LLX_API void llx_model_free(llx_model *model);

    // session
    LLX_API llx_session_params llx_session_default_params(void);
    LLX_API int llx_session_create(llx_model *model, llx_session_params params, llx_session **out_sess);
    LLX_API void llx_session_free(llx_session *sess);
    LLX_API void llx_session_kv_clear(llx_session *sess);

    // LoRA（支持多适配器并行叠加）
    // - 兼容旧接口：加载单个 LoRA（会先清空已应用的 LoRA），再按给定 scale 应用
    LLX_API int llx_session_load_lora(llx_session *sess, const char *lora_path, float scale);
    // - 新接口：追加加载一个 LoRA（不会移除已加载的其它 LoRA）
    LLX_API int llx_session_add_lora(llx_session *sess, const char *lora_path, float scale);
    // - 调整已加载 LoRA 的 scale（按路径匹配）
    LLX_API int llx_session_update_lora_scale(llx_session *sess, const char *lora_path, float scale);
    // - 按路径移除某个 LoRA（若存在）
    LLX_API void llx_session_remove_lora(llx_session *sess, const char *lora_path);
    // - 移除并释放全部已加载的 LoRA
    LLX_API void llx_session_clear_lora(llx_session *sess);

    // 初始化一次生成（两种入口）
    LLX_API int llx_session_init_from_text(llx_session *sess, const char *text, int format_chat, int n_len);
    LLX_API int llx_session_init_from_messages_json(llx_session *sess, const char *messages_json, int n_len);

    // 单步生成（流式）
    // - 写入 UTF-8 片段到 out_utf8（\0 结尾）；若暂不可输出完整 UTF-8，则返回空串
    // - finished!=0 表示生成结束（eog 或已达 n_len）
    LLX_API int llx_session_step(llx_session *sess, int n_len,
                                 char *out_utf8, size_t out_size,
                                 int *finished);

    // 简易基准测试（返回 Markdown 文本，写入 out）
    LLX_API int llx_bench(llx_session *sess, int pp, int tg, int pl, int nr,
                          char *out, size_t out_size);

    // 本地 OpenAI chat/completions 风格：
    // - request_json: OpenAI 兼容的请求 JSON（必须包含 model/messages，可选 tools/tool_choice/temperature/top_p 等）
    // - out_json: 写入 OpenAI 兼容响应 JSON（包含 choices[0].message 或 tool_calls，finish_reason 等）
    // 返回 1 成功，0 失败（错误见 llx_last_error）
    LLX_API int llx_chat_complete_json(llx_session *sess,
                                       const char *request_json,
                                       char *out_json, size_t out_size);

#ifdef __cplusplus
}
#endif
