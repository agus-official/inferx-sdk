package com.inferx.llx

object LLX {
    init {
        try {
            System.loadLibrary("llx-android")
        } catch (t: Throwable) {
            try {
                android.util.Log.e(
                    "LLX",
                    "loadLibrary failed: ${t.message}; SUPPORTED_ABIS=" +
                        android.os.Build.SUPPORTED_ABIS.joinToString(",")
                )
            } catch (_: Throwable) {}
            throw t
        }
    }

    @JvmStatic external fun nativeInitBackend()
    @JvmStatic external fun nativeFreeBackend()
    @JvmStatic external fun nativeModelLoad(path: String): Long
    @JvmStatic external fun nativeModelFree(model: Long)
    @JvmStatic external fun nativeSessionCreate(model: Long, nCtx: Int, nThreads: Int): Long
    @JvmStatic external fun nativeSessionFree(sess: Long)
    @JvmStatic external fun nativeSessionInitFromText(sess: Long, text: String, formatChat: Boolean, nLen: Int): Int
    @JvmStatic external fun nativeSessionInitFromMessagesJson(sess: Long, messagesJson: String, nLen: Int): Int
    @JvmStatic external fun nativeSessionKvClear(sess: Long)
    @JvmStatic external fun nativeChatCompleteJson(sess: Long, requestJson: String): String
    @JvmStatic external fun nativeSessionStep(sess: Long, nLen: Int): StepResult
    @JvmStatic external fun nativeSystemInfo(): String
    @JvmStatic external fun nativeBench(sess: Long, pp: Int, tg: Int, pl: Int, nr: Int): String

    // LoRA
    @JvmStatic external fun nativeSessionLoadLora(sess: Long, path: String, scale: Float): Boolean
    @JvmStatic external fun nativeSessionAddLora(sess: Long, path: String, scale: Float): Boolean
    @JvmStatic external fun nativeSessionUpdateLoraScale(sess: Long, path: String, scale: Float): Boolean
    @JvmStatic external fun nativeSessionRemoveLora(sess: Long, path: String)
    @JvmStatic external fun nativeSessionClearLora(sess: Long)
    @JvmStatic external fun nativeLastError(): String

    data class StepResult(val text: String, val finished: Boolean)
}


