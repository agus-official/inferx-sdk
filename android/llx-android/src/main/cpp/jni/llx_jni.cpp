#include <jni.h>
#include <string>
#include <cstring>
#include "llx.h"

static jlong ptr_to_jlong(void* p) { return reinterpret_cast<jlong>(p); }
template <typename T>
static T* jlong_to_ptr(jlong v) { return reinterpret_cast<T*>(v); }

extern "C" JNIEXPORT void JNICALL
Java_com_inferx_llx_LLX_nativeInitBackend(JNIEnv*, jclass) {
    llx_backend_init();
}

extern "C" JNIEXPORT void JNICALL
Java_com_inferx_llx_LLX_nativeFreeBackend(JNIEnv*, jclass) {
    llx_backend_free();
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_inferx_llx_LLX_nativeModelLoad(JNIEnv* env, jclass, jstring jpath) {
    const char* cpath = env->GetStringUTFChars(jpath, nullptr);
    llx_model* m = nullptr;
    int ok = llx_model_load(cpath, &m);
    env->ReleaseStringUTFChars(jpath, cpath);
    if (!ok) return 0;
    return ptr_to_jlong(m);
}

extern "C" JNIEXPORT void JNICALL
Java_com_inferx_llx_LLX_nativeModelFree(JNIEnv*, jclass, jlong handle) {
    llx_model_free(jlong_to_ptr<llx_model>(handle));
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_inferx_llx_LLX_nativeSessionCreate(JNIEnv*, jclass, jlong modelHandle, jint nCtx, jint nThreads) {
    llx_session_params p = llx_session_default_params();
    if (nCtx > 0) p.n_ctx = nCtx;
    p.n_threads = nThreads;
    llx_session* s = nullptr;
    int ok = llx_session_create(jlong_to_ptr<llx_model>(modelHandle), p, &s);
    if (!ok) return 0;
    return ptr_to_jlong(s);
}

extern "C" JNIEXPORT void JNICALL
Java_com_inferx_llx_LLX_nativeSessionFree(JNIEnv*, jclass, jlong sess) {
    llx_session_free(jlong_to_ptr<llx_session>(sess));
}

extern "C" JNIEXPORT jint JNICALL
Java_com_inferx_llx_LLX_nativeSessionInitFromText(JNIEnv* env, jclass, jlong sess,
                                                  jstring jtext, jboolean formatChat, jint nLen) {
    const char* ctext = env->GetStringUTFChars(jtext, nullptr);
    int r = llx_session_init_from_text(jlong_to_ptr<llx_session>(sess), ctext, formatChat ? 1 : 0, nLen);
    env->ReleaseStringUTFChars(jtext, ctext);
    return r;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_inferx_llx_LLX_nativeSessionInitFromMessagesJson(JNIEnv* env, jclass, jlong sess,
                                                          jstring jmessages, jint nLen) {
    const char* cmessages = env->GetStringUTFChars(jmessages, nullptr);
    int r = llx_session_init_from_messages_json(jlong_to_ptr<llx_session>(sess), cmessages, nLen);
    env->ReleaseStringUTFChars(jmessages, cmessages);
    return r;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_inferx_llx_LLX_nativeChatCompleteJson(JNIEnv* env, jclass, jlong sess, jstring jreq) {
    const char* creq = env->GetStringUTFChars(jreq, nullptr);
    std::string out(1 << 20, '\0');
    int ok = llx_chat_complete_json(jlong_to_ptr<llx_session>(sess), creq, out.data(), out.size());
    env->ReleaseStringUTFChars(jreq, creq);
    if (!ok) {
        const char* err = llx_last_error();
        return env->NewStringUTF(err ? err : "");
    }
    out.resize(strlen(out.c_str()));
    return env->NewStringUTF(out.c_str());
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_inferx_llx_LLX_nativeSessionStep(JNIEnv* env, jclass, jlong sess, jint nLen) {
    char buf[4096];
    int finished = 0;
    int ok = llx_session_step(jlong_to_ptr<llx_session>(sess), nLen, buf, sizeof(buf), &finished);
    if (!ok) {
        const char* err = llx_last_error();
        (void)err;
        finished = 1;
        buf[0] = '\0';
    }
    jclass cls = env->FindClass("com/inferx/llx/LLX$StepResult");
    jmethodID ctor = env->GetMethodID(cls, "<init>", "(Ljava/lang/String;Z)V");
    jstring text = env->NewStringUTF(buf);
    return env->NewObject(cls, ctor, text, finished ? JNI_TRUE : JNI_FALSE);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_inferx_llx_LLX_nativeSystemInfo(JNIEnv* env, jclass) {
    return env->NewStringUTF(llx_system_info());
}

extern "C" JNIEXPORT void JNICALL
Java_com_inferx_llx_LLX_nativeSessionKvClear(JNIEnv*, jclass, jlong sess) {
    llx_session_kv_clear(jlong_to_ptr<llx_session>(sess));
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_inferx_llx_LLX_nativeBench(JNIEnv* env, jclass, jlong sess, jint pp, jint tg, jint pl, jint nr) {
    char buf[4096];
    int ok = llx_bench(jlong_to_ptr<llx_session>(sess), pp, tg, pl, nr, buf, sizeof(buf));
    if (!ok) {
        const char* err = llx_last_error();
        return env->NewStringUTF(err ? err : "");
    }
    return env->NewStringUTF(buf);
}

// ===== LoRA multi-adapter bridging =====
extern "C" JNIEXPORT jboolean JNICALL
Java_com_inferx_llx_LLX_nativeSessionLoadLora(JNIEnv* env, jclass, jlong sess, jstring jpath, jfloat scale) {
    const char* cpath = env->GetStringUTFChars(jpath, nullptr);
    int ok = llx_session_load_lora(jlong_to_ptr<llx_session>(sess), cpath, (float)scale);
    env->ReleaseStringUTFChars(jpath, cpath);
    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_inferx_llx_LLX_nativeSessionAddLora(JNIEnv* env, jclass, jlong sess, jstring jpath, jfloat scale) {
    const char* cpath = env->GetStringUTFChars(jpath, nullptr);
    int ok = llx_session_add_lora(jlong_to_ptr<llx_session>(sess), cpath, (float)scale);
    env->ReleaseStringUTFChars(jpath, cpath);
    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_inferx_llx_LLX_nativeSessionUpdateLoraScale(JNIEnv* env, jclass, jlong sess, jstring jpath, jfloat scale) {
    const char* cpath = env->GetStringUTFChars(jpath, nullptr);
    int ok = llx_session_update_lora_scale(jlong_to_ptr<llx_session>(sess), cpath, (float)scale);
    env->ReleaseStringUTFChars(jpath, cpath);
    return ok ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_inferx_llx_LLX_nativeSessionRemoveLora(JNIEnv* env, jclass, jlong sess, jstring jpath) {
    const char* cpath = env->GetStringUTFChars(jpath, nullptr);
    llx_session_remove_lora(jlong_to_ptr<llx_session>(sess), cpath);
    env->ReleaseStringUTFChars(jpath, cpath);
}

extern "C" JNIEXPORT void JNICALL
Java_com_inferx_llx_LLX_nativeSessionClearLora(JNIEnv*, jclass, jlong sess) {
    llx_session_clear_lora(jlong_to_ptr<llx_session>(sess));
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_inferx_llx_LLX_nativeLastError(JNIEnv* env, jclass) {
    const char* err = llx_last_error();
    return env->NewStringUTF(err ? err : "");
}


