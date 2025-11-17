package com.inferx.example

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.inferx.llx.LLX
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

class MainViewModel: ViewModel() {
    data class ChatMessage(val role: String, val content: String)
    data class LoraItem(val path: String, var scale: Float)

    var uiMessages by mutableStateOf(listOf<ChatMessage>())
        private set

    var message by mutableStateOf("")
        private set

    var isModelLoaded by mutableStateOf(false)
        private set
    var isGenerating by mutableStateOf(false)
        private set

    private var modelHandle: Long = 0L
    private var sessionHandle: Long = 0L

    private var chatHistory: MutableList<Map<String, String>> = mutableListOf()

    // LoRA 状态（UI 展示）
    var loras by mutableStateOf(listOf<LoraItem>())
        private set

    fun updateMessage(newMessage: String) { message = newMessage }

    fun log(s: String) {
        uiMessages = uiMessages + ChatMessage("system", s)
    }

    fun clear() {
        uiMessages = listOf()
        chatHistory.clear()
        isGenerating = false
        if (sessionHandle != 0L) {
            LLX.nativeSessionKvClear(sessionHandle)
        }
    }

    fun clearAllLora() {
        if (sessionHandle == 0L) return
        LLX.nativeSessionClearLora(sessionHandle)
        loras = listOf()
        log("已清空 LoRA 适配器")
    }

    fun addOrUpdateLora(path: String, scale: Float) {
        if (sessionHandle == 0L) return
        val existing = loras.indexOfFirst { it.path == path }
        val s = if (scale <= 0f) 1f else scale
        val ok = if (existing >= 0) {
            LLX.nativeSessionUpdateLoraScale(sessionHandle, path, s)
        } else {
            LLX.nativeSessionAddLora(sessionHandle, path, s)
        }
        if (ok) {
            if (existing >= 0) {
                val updated = loras.toMutableList()
                updated[existing] = updated[existing].copy(scale = s)
                loras = updated
                log("更新 LoRA scale: ${path} -> ${s}")
            } else {
                loras = loras + LoraItem(path, s)
                log("加载 LoRA: ${path} (scale=${s})")
            }
        } else {
            log("LoRA 失败: ${LLX.nativeLastError()}")
        }
    }

    fun removeLora(path: String) {
        if (sessionHandle == 0L) return
        LLX.nativeSessionRemoveLora(sessionHandle, path)
        loras = loras.filterNot { it.path == path }
        log("移除 LoRA: ${path}")
    }

    fun copyAllToClipboard(clipboard: ClipboardManager) {
        val text = uiMessages.joinToString("\n") { it.role + ": " + it.content }
        clipboard.setPrimaryClip(ClipData.newPlainText("", text))
    }

    fun copyAndLoadModel(context: Context, uri: Uri) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val name = run {
                    var displayName: String? = null
                    val cursor = context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
                    cursor?.use {
                        if (it.moveToFirst()) {
                            val idx = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            if (idx >= 0) displayName = it.getString(idx)
                        }
                    }
                    (displayName ?: "model.gguf").let { if (it.endsWith(".gguf")) it else "$it.gguf" }
                }

                val dest = File(context.getExternalFilesDir(null), name)
                context.contentResolver.openInputStream(uri)?.use { input: InputStream ->
                    FileOutputStream(dest).use { output -> input.copyTo(output) }
                }
                withContext(Dispatchers.Main) {
                    log("Copied model to ${dest.path}")
                    load(dest.path)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { log("Failed to copy model: ${e.message}") }
            }
        }
    }

    fun copyAndAddLora(context: Context, uri: Uri, defaultScale: Float = 1f) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val name = run {
                    var displayName: String? = null
                    val cursor = context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
                    cursor?.use {
                        if (it.moveToFirst()) {
                            val idx = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            if (idx >= 0) displayName = it.getString(idx)
                        }
                    }
                    (displayName ?: "adapter.gguf").let { if (it.endsWith(".gguf")) it else "$it.gguf" }
                }
                val dest = File(context.getExternalFilesDir(null), name)
                context.contentResolver.openInputStream(uri)?.use { input: InputStream ->
                    FileOutputStream(dest).use { output -> input.copyTo(output) }
                }
                withContext(Dispatchers.Main) {
                    addOrUpdateLora(dest.path, defaultScale)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { log("LoRA 导入失败: ${e.message}") }
            }
        }
    }

    fun load(pathToModel: String) {
        viewModelScope.launch(Dispatchers.Default) {
            try {
                if (modelHandle != 0L) throw IllegalStateException("Model already loaded")
                LLX.nativeInitBackend()
                modelHandle = LLX.nativeModelLoad(pathToModel)
                if (modelHandle == 0L) throw IllegalStateException("nativeModelLoad failed")
                sessionHandle = LLX.nativeSessionCreate(modelHandle, 8192, 0)
                if (sessionHandle == 0L) throw IllegalStateException("nativeSessionCreate failed")
                withContext(Dispatchers.Main) {
                    isModelLoaded = true
                    log("Loaded $pathToModel")
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { log(e.message ?: "load failed") }
            }
        }
    }

    fun send() {
        val text = message
        message = ""
        if (text.isBlank()) return

        // UI 先追加 user 与占位 assistant
        uiMessages = uiMessages + ChatMessage("user", text) + ChatMessage("assistant", "")
        if (sessionHandle == 0L || !isModelLoaded) return
        if (isGenerating) return

        viewModelScope.launch(Dispatchers.Default) {
            try {
                isGenerating = true
                chatHistory.add(mapOf("role" to "user", "content" to text))
                val messagesJson = chatHistory.joinToString(prefix = "[", postfix = "]", separator = ",") { msg ->
                    val role = escapeJson(msg["role"] ?: "user")
                    val content = escapeJson(msg["content"] ?: "")
                    "{\"role\":\"$role\",\"content\":\"$content\"}"
                }

                // 初始化为聊天上下文
                LLX.nativeSessionInitFromMessagesJson(sessionHandle, messagesJson, 1024)

                val sb = StringBuilder()
                while (true) {
                    val r = LLX.nativeSessionStep(sessionHandle, 1024)
                    if (r.text.isNotEmpty()) {
                        sb.append(r.text)
                        withContext(Dispatchers.Main) {
                            val lastIdx = uiMessages.lastIndex
                            if (lastIdx >= 0 && uiMessages[lastIdx].role == "assistant") {
                                val updated = uiMessages[lastIdx].copy(content = sb.toString())
                                uiMessages = uiMessages.dropLast(1) + updated
                            }
                        }
                    }
                    if (r.finished) break
                }

                withContext(Dispatchers.Main) {
                    val reply = sb.toString()
                    if (reply.isNotEmpty()) chatHistory.add(mapOf("role" to "assistant", "content" to reply))
                }
            } finally {
                withContext(Dispatchers.Main) { isGenerating = false }
                LLX.nativeSessionKvClear(sessionHandle)
            }
        }
    }

    fun bench(pp: Int, tg: Int, pl: Int) {
        if (sessionHandle == 0L) return
        viewModelScope.launch(Dispatchers.Default) {
            val result = LLX.nativeBench(sessionHandle, pp, tg, pl, 1)
            withContext(Dispatchers.Main) { log(result) }
        }
    }

    override fun onCleared() {
        super.onCleared()
        viewModelScope.launch(Dispatchers.Default) {
            try {
                if (sessionHandle != 0L) {
                    LLX.nativeSessionFree(sessionHandle)
                    sessionHandle = 0L
                }
            } finally {
                if (modelHandle != 0L) {
                    LLX.nativeModelFree(modelHandle)
                    modelHandle = 0L
                }
                LLX.nativeFreeBackend()
            }
        }
    }

    private fun escapeJson(s: String): String {
        return s
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }
}


