package com.inferx.llx_flutter

import com.inferx.llx.LLX
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/** LlxFlutterPlugin */
class LlxFlutterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    // 串行执行，避免底层非线程安全；如需并发，可改为线程池
    private val executor = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "llx_flutter")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "initBackend" -> {
                    executor.execute {
                        try {
                            LLX.nativeInitBackend()
                            mainHandler.post { result.success(null) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "freeBackend" -> {
                    executor.execute {
                        try {
                            LLX.nativeFreeBackend()
                            mainHandler.post { result.success(null) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "modelLoad" -> {
                    val path = call.argument<String>("path")
                        ?: return result.error("INVALID_ARGUMENT", "path is required", null)
                    executor.execute {
                        try {
                            val handle = LLX.nativeModelLoad(path)
                            mainHandler.post { result.success(handle) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "modelFree" -> {
                    val handle = call.argument<Number>("modelHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "modelHandle is required", null)
                    executor.execute {
                        try {
                            LLX.nativeModelFree(handle)
                            mainHandler.post { result.success(null) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionCreate" -> {
                    val modelHandle = call.argument<Number>("modelHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "modelHandle is required", null)
                    val nCtx = call.argument<Number>("nCtx")?.toInt() ?: 8192
                    val nThreads = call.argument<Number>("nThreads")?.toInt() ?: 0
                    executor.execute {
                        try {
                            val handle = LLX.nativeSessionCreate(modelHandle, nCtx, nThreads)
                            mainHandler.post { result.success(handle) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionFree" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    executor.execute {
                        try {
                            LLX.nativeSessionFree(handle)
                            mainHandler.post { result.success(null) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionInitFromText" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    val text = call.argument<String>("text")
                        ?: return result.error("INVALID_ARGUMENT", "text is required", null)
                    val formatChat = call.argument<Boolean>("formatChat") ?: true
                    val nLen = call.argument<Number>("nLen")?.toInt() ?: 1024
                    executor.execute {
                        try {
                            val tokCount = LLX.nativeSessionInitFromText(handle, text, formatChat, nLen)
                            mainHandler.post { result.success(tokCount) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionInitFromMessagesJson" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    val messagesJson = call.argument<String>("messagesJson")
                        ?: return result.error("INVALID_ARGUMENT", "messagesJson is required", null)
                    val nLen = call.argument<Number>("nLen")?.toInt() ?: 1024
                    executor.execute {
                        try {
                            val tokCount = LLX.nativeSessionInitFromMessagesJson(handle, messagesJson, nLen)
                            mainHandler.post { result.success(tokCount) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionKvClear" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    executor.execute {
                        try {
                            LLX.nativeSessionKvClear(handle)
                            mainHandler.post { result.success(null) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionStep" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    val nLen = call.argument<Number>("nLen")?.toInt() ?: 1024
                    executor.execute {
                        try {
                            val stepResult = LLX.nativeSessionStep(handle, nLen)
                            val resultMap = mapOf(
                                "text" to stepResult.text,
                                "finished" to stepResult.finished
                            )
                            mainHandler.post { result.success(resultMap) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "chatCompleteJson" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    val requestJson = call.argument<String>("requestJson")
                        ?: return result.error("INVALID_ARGUMENT", "requestJson is required", null)
                    executor.execute {
                        try {
                            val responseJson = LLX.nativeChatCompleteJson(handle, requestJson)
                            mainHandler.post { result.success(responseJson) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "systemInfo" -> {
                    executor.execute {
                        try {
                            val info = LLX.nativeSystemInfo()
                            mainHandler.post { result.success(info) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "bench" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    val pp = call.argument<Number>("pp")?.toInt() ?: 8
                    val tg = call.argument<Number>("tg")?.toInt() ?: 4
                    val pl = call.argument<Number>("pl")?.toInt() ?: 1
                    val nr = call.argument<Number>("nr")?.toInt() ?: 1
                    executor.execute {
                        try {
                            val benchResult = LLX.nativeBench(handle, pp, tg, pl, nr)
                            mainHandler.post { result.success(benchResult) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionLoadLora" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    val loraPath = call.argument<String>("loraPath")
                        ?: return result.error("INVALID_ARGUMENT", "loraPath is required", null)
                    val scale = call.argument<Number>("scale")?.toFloat() ?: 1.0f
                    executor.execute {
                        try {
                            val success = LLX.nativeSessionLoadLora(handle, loraPath, scale)
                            mainHandler.post { result.success(success) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionAddLora" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    val loraPath = call.argument<String>("loraPath")
                        ?: return result.error("INVALID_ARGUMENT", "loraPath is required", null)
                    val scale = call.argument<Number>("scale")?.toFloat() ?: 1.0f
                    executor.execute {
                        try {
                            val success = LLX.nativeSessionAddLora(handle, loraPath, scale)
                            mainHandler.post { result.success(success) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionUpdateLoraScale" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    val loraPath = call.argument<String>("loraPath")
                        ?: return result.error("INVALID_ARGUMENT", "loraPath is required", null)
                    val scale = call.argument<Number>("scale")?.toFloat() ?: 1.0f
                    executor.execute {
                        try {
                            val success = LLX.nativeSessionUpdateLoraScale(handle, loraPath, scale)
                            mainHandler.post { result.success(success) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionRemoveLora" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    val loraPath = call.argument<String>("loraPath")
                        ?: return result.error("INVALID_ARGUMENT", "loraPath is required", null)
                    executor.execute {
                        try {
                            LLX.nativeSessionRemoveLora(handle, loraPath)
                            mainHandler.post { result.success(null) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "sessionClearLora" -> {
                    val handle = call.argument<Number>("sessionHandle")?.toLong()
                        ?: return result.error("INVALID_ARGUMENT", "sessionHandle is required", null)
                    executor.execute {
                        try {
                            LLX.nativeSessionClearLora(handle)
                            mainHandler.post { result.success(null) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                "lastError" -> {
                    executor.execute {
                        try {
                            val error = LLX.nativeLastError()
                            mainHandler.post { result.success(error) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("ERROR", e.message ?: "Unknown error", null) }
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            result.error("ERROR", e.message ?: "Unknown error", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}

