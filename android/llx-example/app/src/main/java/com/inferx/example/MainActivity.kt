package com.inferx.example

import android.app.ActivityManager
import android.app.DownloadManager
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.format.Formatter
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.imePadding
import androidx.compose.material3.Slider
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.material3.MaterialTheme as M3Theme
import androidx.compose.ui.graphics.toArgb
import androidx.core.content.getSystemService
import com.inferx.llx.LLX
import io.noties.markwon.Markwon

class MainActivity: ComponentActivity() {
    private val activityManager by lazy { getSystemService<ActivityManager>()!! }
    private val clipboardManager by lazy { getSystemService<ClipboardManager>()!! }
    private val downloadManager by lazy { getSystemService<DownloadManager>()!! }

    private val viewModel: MainViewModel by viewModels()

    private fun availableMemory(): ActivityManager.MemoryInfo {
        return ActivityManager.MemoryInfo().also { activityManager.getMemoryInfo(it) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val free = Formatter.formatFileSize(this, availableMemory().availMem)
        val total = Formatter.formatFileSize(this, availableMemory().totalMem)

        viewModel.log("Current memory: $free / $total")
        viewModel.log("App files directory: ${getExternalFilesDir(null)}")

        setContent {
            M3Theme {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    MainCompose(viewModel, clipboardManager, downloadManager)
                }
            }
        }
    }
}

@Composable
fun MainCompose(viewModel: MainViewModel, clipboard: ClipboardManager, dm: DownloadManager) {
    Column(modifier = Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp)) {
            val statusModel = if (viewModel.isModelLoaded) "已加载" else "未加载"
            val statusGen = if (viewModel.isGenerating) "生成中…" else "空闲"
            Text("状态：$statusModel · $statusGen", style = MaterialTheme.typography.labelMedium, color = LocalContentColor.current)
        }
        val scrollState = rememberLazyListState()
        val context = LocalContext.current
        val coroutineScope = rememberCoroutineScope()

        val pickModelLauncher = rememberLauncherForActivityResult(
            contract = ActivityResultContracts.OpenDocument()
        ) { uri: Uri? ->
            if (uri != null) {
                viewModel.copyAndLoadModel(context, uri)
            }
        }

        val pickLoraLauncher = rememberLauncherForActivityResult(
            contract = ActivityResultContracts.OpenDocument()
        ) { uri: Uri? ->
            if (uri != null) {
                viewModel.copyAndAddLora(context, uri)
            }
        }

        Box(modifier = Modifier.weight(1f)) {
            LazyColumn(state = scrollState, verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxSize().padding(12.dp)) {
                items(viewModel.uiMessages) { msg ->
                    val isUser = msg.role == "user"
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start) {
                        val bubbleColor = if (isUser) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant
                        val contentColor = if (isUser) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant
                        Box(
                            modifier = Modifier
                                .clip(MaterialTheme.shapes.medium)
                                .background(bubbleColor)
                                .padding(12.dp)
                                .fillMaxWidth(0.85f)
                        ) {
                            val markwon = remember { Markwon.create(context) }
                            AndroidView(
                                factory = { android.widget.TextView(it).apply { setTextColor(contentColor.toArgb()) } },
                                update = { tv -> markwon.setMarkdown(tv, msg.content) }
                            )
                        }
                    }
                }
                item {
                    Spacer(Modifier.size(4.dp))
                    Text("LoRA 适配器", style = MaterialTheme.typography.titleSmall, color = LocalContentColor.current)
                }
                items(viewModel.loras) { item ->
                    Column(modifier = Modifier.fillMaxWidth().clip(MaterialTheme.shapes.medium).background(MaterialTheme.colorScheme.surfaceVariant).padding(12.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(item.path, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
                            IconButton(onClick = { viewModel.removeLora(item.path) }) {
                                Icon(Icons.Filled.Delete, contentDescription = "Remove")
                            }
                        }
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(text = "scale: ${"" + String.format("%.2f", item.scale)}", style = MaterialTheme.typography.labelSmall)
                        }
                        Slider(
                            value = item.scale,
                            onValueChange = { v: Float -> viewModel.addOrUpdateLora(item.path, v) },
                            valueRange = 0.1f..2.0f
                        )
                    }
                }
                item { Spacer(Modifier.size(4.dp)) }
            }
            LaunchedEffect(viewModel.uiMessages.lastOrNull()?.content) {
                val layoutInfo = scrollState.layoutInfo
                val total = layoutInfo.totalItemsCount
                if (total > 0) {
                    val lastIndex = total - 1
                    val lastItem = layoutInfo.visibleItemsInfo.find { it.index == lastIndex }
                    val isAtBottom = lastItem?.let {
                        val itemEnd = it.offset + it.size
                        val viewportEnd = layoutInfo.viewportEndOffset
                        itemEnd <= viewportEnd + 8
                    } ?: false
                    if (isAtBottom) {
                        scrollState.scrollToItem(lastIndex, Int.MAX_VALUE)
                    }
                }
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .imePadding()
                .padding(horizontal = 12.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedTextField(
                value = viewModel.message,
                onValueChange = { viewModel.updateMessage(it) },
                modifier = Modifier.weight(1f),
                placeholder = { Text("输入消息…") },
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = MaterialTheme.colorScheme.surface,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                    focusedTextColor = MaterialTheme.colorScheme.onSurface,
                    unfocusedTextColor = MaterialTheme.colorScheme.onSurface,
                    focusedIndicatorColor = MaterialTheme.colorScheme.primary,
                    unfocusedIndicatorColor = MaterialTheme.colorScheme.outline
                )
            )
            Button(onClick = { viewModel.send() }, enabled = viewModel.isModelLoaded && !viewModel.isGenerating) { Text(if (viewModel.isGenerating) "生成中…" else "发送") }
        }
        Spacer(Modifier.size(4.dp))
        Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { viewModel.clear() }, enabled = !viewModel.isGenerating) { Text("清空") }
            Button(onClick = { viewModel.bench(8, 4, 1) }) { Text("Bench") }
            Button(onClick = { pickModelLauncher.launch(arrayOf("*/*")) }, enabled = !viewModel.isGenerating) { Text("GGUF") }
            Button(onClick = { pickLoraLauncher.launch(arrayOf("*/*")) }, enabled = viewModel.isModelLoaded && !viewModel.isGenerating) { Text("添加LoRA") }
            Button(onClick = { viewModel.clearAllLora() }, enabled = viewModel.loras.isNotEmpty() && !viewModel.isGenerating) { Text("清空LoRA") }
            Button(onClick = { viewModel.copyAllToClipboard(clipboard) }) { Text("复制") }
            DownloadableButtons(viewModel, dm)
        }
    }
}

@Composable
private fun DownloadableButtons(viewModel: MainViewModel, dm: DownloadManager) {
    // 可选：提供几个预置下载项（使用与 llama.android 类似的结构）
    // 这里先留空或后续添加具体源
}
