# generate_phase5.ps1
# TicTube Wear OS - Phase 5: History, Quality, Downloads, Playlists, Comments
# Run from project root: S:\_Vibe_Coding\TicTube\WearApp
#
# Creates/Overwrites 6 files:
#   1. HistoryManager.kt   (NEW)
#   2. SettingsManager.kt   (NEW)
#   3. DownloadManager.kt   (NEW)
#   4. MainScreen.kt        (OVERWRITE)
#   5. PlayerScreen.kt      (OVERWRITE)
#   6. MainActivity.kt      (OVERWRITE)

$ErrorActionPreference = "Stop"
$basePath = Join-Path $PSScriptRoot "app\src\main\java\com\tictube"
if (-not (Test-Path $basePath)) { New-Item -ItemType Directory -Force -Path $basePath | Out-Null }
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Emit($name, $content) {
    $p = Join-Path $basePath $name
    [System.IO.File]::WriteAllText($p, $content, $utf8)
    Write-Host "  [OK] $name" -ForegroundColor Green
}

Write-Host "================================================" -ForegroundColor Cyan
Write-Host " TicTube Phase 5 - Ultimate Standalone Client    " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. HistoryManager.kt
# ============================================================
Emit "HistoryManager.kt" @'
package com.tictube

import android.content.Context

data class HistoryEntry(val url: String, val title: String, val timestamp: Long)

class HistoryManager private constructor(context: Context) {

    companion object {
        private const val PREFS = "tictube_history"
        private const val KEY = "watch_history"
        private const val SEP = "||"
        private const val MAX = 50

        @Volatile private var instance: HistoryManager? = null
        fun getInstance(ctx: Context): HistoryManager =
            instance ?: synchronized(this) {
                instance ?: HistoryManager(ctx.applicationContext).also { instance = it }
            }
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun add(url: String, title: String) {
        if (url.isBlank()) return
        val set = raw().toMutableSet()
        set.removeAll { it.contains("$SEP$url$SEP") }
        set.add("${System.currentTimeMillis()}$SEP$url$SEP$title")
        val trimmed = set.sortedByDescending {
            it.substringBefore(SEP).toLongOrNull() ?: 0L
        }.take(MAX).toSet()
        prefs.edit().putStringSet(KEY, trimmed).apply()
    }

    fun getAll(): List<HistoryEntry> = raw().mapNotNull { e ->
        val p = e.split(SEP, limit = 3)
        if (p.size == 3) HistoryEntry(p[1], p[2], p[0].toLongOrNull() ?: 0L) else null
    }.sortedByDescending { it.timestamp }

    fun clear() { prefs.edit().remove(KEY).apply() }

    private fun raw(): Set<String> = prefs.getStringSet(KEY, emptySet()) ?: emptySet()
}
'@

# ============================================================
# 2. SettingsManager.kt
# ============================================================
Emit "SettingsManager.kt" @'
package com.tictube

import android.content.Context

class SettingsManager private constructor(context: Context) {

    enum class StreamQuality(val label: String) {
        AUDIO_ONLY("Audio Only \uD83C\uDFA7"),
        Q360P("360p"),
        Q720P("720p")
    }

    companion object {
        private const val PREFS = "tictube_settings"
        private const val KEY_Q = "stream_quality"

        @Volatile private var instance: SettingsManager? = null
        fun getInstance(ctx: Context): SettingsManager =
            instance ?: synchronized(this) {
                instance ?: SettingsManager(ctx.applicationContext).also { instance = it }
            }
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun getQuality(): StreamQuality = try {
        StreamQuality.valueOf(prefs.getString(KEY_Q, StreamQuality.Q360P.name)!!)
    } catch (_: Exception) { StreamQuality.Q360P }

    fun setQuality(q: StreamQuality) { prefs.edit().putString(KEY_Q, q.name).apply() }

    fun cycleQuality(): StreamQuality {
        val next = when (getQuality()) {
            StreamQuality.Q360P -> StreamQuality.Q720P
            StreamQuality.Q720P -> StreamQuality.AUDIO_ONLY
            StreamQuality.AUDIO_ONLY -> StreamQuality.Q360P
        }
        setQuality(next)
        return next
    }
}
'@

# ============================================================
# 3. DownloadManager.kt
# ============================================================
Emit "DownloadManager.kt" @'
package com.tictube

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

data class DownloadEntry(val fileName: String, val title: String, val filePath: String)

class DownloadManager private constructor(private val context: Context) {

    companion object {
        private const val PREFS = "tictube_downloads"
        private const val KEY = "downloaded_files"
        private const val SEP = "||"

        @Volatile private var instance: DownloadManager? = null
        fun getInstance(ctx: Context): DownloadManager =
            instance ?: synchronized(this) {
                instance ?: DownloadManager(ctx.applicationContext).also { instance = it }
            }
    }

    private val dir = File(context.filesDir, "downloads").apply { mkdirs() }
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    suspend fun download(streamUrl: String, title: String): DownloadEntry =
        withContext(Dispatchers.IO) {
            val safe = title.replace(Regex("[^a-zA-Z0-9._-]"), "_").take(40)
            val ext = if (streamUrl.contains("audio", true) ||
                streamUrl.contains("m4a", true)) ".m4a" else ".mp4"
            val name = "${safe}_${System.currentTimeMillis()}$ext"
            val file = File(dir, name)

            val conn = URL(streamUrl).openConnection() as HttpURLConnection
            conn.connectTimeout = 30_000
            conn.readTimeout = 120_000
            conn.instanceFollowRedirects = true
            conn.setRequestProperty("User-Agent",
                "Mozilla/5.0 (Windows NT 10.0; rv:102.0) Gecko/20100101 Firefox/102.0")

            conn.inputStream.use { inp -> file.outputStream().use { inp.copyTo(it, 8192) } }

            val entry = DownloadEntry(name, title, file.absolutePath)
            val set = (prefs.getStringSet(KEY, emptySet()) ?: emptySet()).toMutableSet()
            set.add("$name$SEP$title")
            prefs.edit().putStringSet(KEY, set).apply()
            entry
        }

    fun getAll(): List<DownloadEntry> {
        val set = prefs.getStringSet(KEY, emptySet()) ?: emptySet()
        return set.mapNotNull { e ->
            val p = e.split(SEP, limit = 2)
            if (p.size == 2) {
                val f = File(dir, p[0])
                if (f.exists()) DownloadEntry(p[0], p[1], f.absolutePath) else null
            } else null
        }.sortedByDescending { it.fileName }
    }

    fun delete(fileName: String) {
        File(dir, fileName).delete()
        val set = (prefs.getStringSet(KEY, emptySet()) ?: emptySet()).toMutableSet()
        set.removeAll { it.startsWith("$fileName$SEP") }
        prefs.edit().putStringSet(KEY, set).apply()
    }
}
'@

# ============================================================
# 4. MainScreen.kt
# ============================================================
Emit "MainScreen.kt" @'
package com.tictube

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.speech.RecognizerIntent
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.ScalingLazyColumn
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import androidx.wear.compose.material.rememberScalingLazyListState
import coil.compose.AsyncImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.InfoItem
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.playlist.PlaylistInfoItem
import org.schabi.newpipe.extractor.stream.StreamInfoItem

// ─── Data ─────────────────────────────────────────────────────

enum class ItemType { VIDEO, PLAYLIST }

data class VideoItem(
    val id: String,
    val title: String,
    val channel: String,
    val durationText: String,
    val thumbnailUrl: String = "",
    val videoUrl: String = "",
    val type: ItemType = ItemType.VIDEO
)

sealed interface UiState {
    object Loading : UiState
    data class Videos(val videos: List<VideoItem>) : UiState
    data class Channels(val subs: List<Subscription>) : UiState
    data class History(val entries: List<HistoryEntry>) : UiState
    data class Downloads(val entries: List<DownloadEntry>) : UiState
    data class Error(val message: String) : UiState
}

enum class ScreenMode { FEED, SUBSCRIPTIONS, CHANNEL, HISTORY, DOWNLOADS, PLAYLIST }

// ─── ViewModel ────────────────────────────────────────────────

class MainViewModel(app: Application) : AndroidViewModel(app) {

    companion object { private const val TAG = "MainVM"; private const val MAX = 20 }

    private val subMgr = SubscriptionManager.getInstance(app)
    private val histMgr = HistoryManager.getInstance(app)
    private val dlMgr = DownloadManager.getInstance(app)
    val settingsMgr = SettingsManager.getInstance(app)

    private val _mode = MutableStateFlow(ScreenMode.FEED)
    val mode: StateFlow<ScreenMode> = _mode.asStateFlow()
    private val _ui = MutableStateFlow<UiState>(UiState.Loading)
    val ui: StateFlow<UiState> = _ui.asStateFlow()
    private val _header = MutableStateFlow("")
    val header: StateFlow<String> = _header.asStateFlow()
    private val _quality = MutableStateFlow(settingsMgr.getQuality())
    val quality: StateFlow<SettingsManager.StreamQuality> = _quality.asStateFlow()

    private var lastQuery = "Tech News"
    init { search(lastQuery) }

    fun search(query: String) {
        lastQuery = query; _mode.value = ScreenMode.FEED
        _header.value = "\uD83D\uDD0D $query"
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val ext = ServiceList.YouTube.getSearchExtractor(query)
                    ext.fetchPage()
                    ext.initialPage.items.mapNotNull { it.toItem() }.take(MAX)
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("No results") else UiState.Videos(vids)
            } catch (e: Exception) {
                Log.e(TAG, "search", e); _ui.value = UiState.Error(e.localizedMessage ?: "Search failed")
            }
        }
    }

    fun showSubscriptions() {
        _mode.value = ScreenMode.SUBSCRIPTIONS; _header.value = "\u2764\uFE0F My Channels"
        val s = subMgr.getAll()
        _ui.value = if (s.isEmpty()) UiState.Error("No subscriptions yet.\nSubscribe from the player!") else UiState.Channels(s)
    }

    fun showHistory() {
        _mode.value = ScreenMode.HISTORY; _header.value = "\uD83D\uDD52 History"
        val h = histMgr.getAll()
        _ui.value = if (h.isEmpty()) UiState.Error("No history yet.") else UiState.History(h)
    }

    fun showDownloads() {
        _mode.value = ScreenMode.DOWNLOADS; _header.value = "\uD83D\uDCBE Downloads"
        val d = dlMgr.getAll()
        _ui.value = if (d.isEmpty()) UiState.Error("No downloads yet.\nSave videos from the player!") else UiState.Downloads(d)
    }

    fun loadChannel(url: String, name: String) {
        _mode.value = ScreenMode.CHANNEL; _header.value = name
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val ce = ServiceList.YouTube.getChannelExtractor(url); ce.fetchPage()
                    val tab = ce.tabs.firstOrNull { t ->
                        t.contentFilters.any { it.contains("videos", true) }
                    } ?: ce.tabs.firstOrNull() ?: throw Exception("No tabs")
                    val te = ServiceList.YouTube.getChannelTabExtractor(tab); te.fetchPage()
                    te.initialPage.items.filterIsInstance<StreamInfoItem>().take(MAX).map { it.toVideoItem() }
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("No videos") else UiState.Videos(vids)
            } catch (e: Exception) {
                Log.e(TAG, "channel", e); _ui.value = UiState.Error(e.localizedMessage ?: "Failed")
            }
        }
    }

    fun loadPlaylist(url: String) {
        _mode.value = ScreenMode.PLAYLIST; _header.value = "\uD83C\uDFB5 Playlist"
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val pe = ServiceList.YouTube.getPlaylistExtractor(url); pe.fetchPage()
                    _header.value = "\uD83C\uDFB5 ${pe.name}"
                    pe.initialPage.items.filterIsInstance<StreamInfoItem>().map { it.toVideoItem() }
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("Empty playlist") else UiState.Videos(vids)
            } catch (e: Exception) {
                Log.e(TAG, "playlist", e); _ui.value = UiState.Error(e.localizedMessage ?: "Failed")
            }
        }
    }

    fun cycleQuality() { _quality.value = settingsMgr.cycleQuality() }

    fun goBack() { when (_mode.value) {
        ScreenMode.CHANNEL -> showSubscriptions()
        else -> search(lastQuery)
    }}

    fun retry() { when (_mode.value) {
        ScreenMode.FEED, ScreenMode.PLAYLIST -> search(lastQuery)
        ScreenMode.SUBSCRIPTIONS -> showSubscriptions()
        ScreenMode.HISTORY -> showHistory()
        ScreenMode.DOWNLOADS -> showDownloads()
        else -> search(lastQuery)
    }}

    private fun InfoItem.toItem(): VideoItem? = when (this) {
        is StreamInfoItem -> toVideoItem()
        is PlaylistInfoItem -> VideoItem(url, "\uD83C\uDFB5 $name", uploaderName.orEmpty(),
            "${streamCount} videos", thumbnails.firstOrNull()?.url.orEmpty(), url, ItemType.PLAYLIST)
        else -> null
    }

    private fun StreamInfoItem.toVideoItem() = VideoItem(url, name, uploaderName.orEmpty(),
        fmtDur(duration), thumbnails.firstOrNull()?.url.orEmpty(), url, ItemType.VIDEO)
}

private fun fmtDur(s: Long): String {
    if (s < 0) return "LIVE"
    val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
    return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%d:%02d", m, sec)
}

// ─── Composable ───────────────────────────────────────────────

@Composable
fun MainScreen(viewModel: MainViewModel = viewModel()) {
    val ui by viewModel.ui.collectAsState()
    val mode by viewModel.mode.collectAsState()
    val header by viewModel.header.collectAsState()
    val quality by viewModel.quality.collectAsState()
    val listState = rememberScalingLazyListState()
    val focus = remember { FocusRequester() }
    val ctx = LocalContext.current
    val histMgr = remember { HistoryManager.getInstance(ctx.applicationContext) }

    val speechLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()?.takeIf { it.isNotBlank() }?.let { viewModel.search(it) }
        }
    }

    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) }
    ) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize()
                .rotaryScrollable(
                    behavior = RotaryScrollableDefaults.behavior(scrollableState = listState),
                    focusRequester = focus
                ).focusRequester(focus).focusable()
        ) {
            // ── Search chip ──
            item {
                Chip(onClick = {
                    try {
                        speechLauncher.launch(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                            putExtra(RecognizerIntent.EXTRA_PROMPT, "Search YouTube")
                        })
                    } catch (e: Exception) { Log.e("Main", "speech", e) }
                }, label = { Text("\uD83D\uDD0D Search YouTube") },
                    colors = ChipDefaults.primaryChipColors(), modifier = Modifier.fillMaxWidth())
            }

            // ── Navigation chips ──
            if (mode == ScreenMode.FEED) {
                item { Chip(onClick = { viewModel.showSubscriptions() },
                    label = { Text("\u2764\uFE0F Subscriptions") },
                    colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                item { Chip(onClick = { viewModel.showHistory() },
                    label = { Text("\uD83D\uDD52 History") },
                    colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                item { Chip(onClick = { viewModel.showDownloads() },
                    label = { Text("\uD83D\uDCBE Downloads") },
                    colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                item { CompactChip(onClick = { viewModel.cycleQuality() },
                    label = { Text("\u2699\uFE0F Quality: ${quality.label}") },
                    colors = ChipDefaults.secondaryChipColors()) }
            } else {
                item { Chip(onClick = { viewModel.goBack() },
                    label = { Text("\u2190 Back") },
                    colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
            }

            // ── Header ──
            item { Text(header, style = MaterialTheme.typography.caption1,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }

            // ── Content ──
            when (val s = ui) {
                is UiState.Loading -> item {
                    Box(Modifier.fillMaxWidth().height(80.dp), contentAlignment = Alignment.Center) {
                        Text("Loading\u2026", style = MaterialTheme.typography.body1) }
                }
                is UiState.Error -> item {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(s.message, style = MaterialTheme.typography.body2, textAlign = TextAlign.Center,
                            maxLines = 4, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.height(4.dp))
                        Chip(onClick = { viewModel.retry() }, label = { Text("Retry") },
                            colors = ChipDefaults.primaryChipColors())
                    }
                }
                is UiState.Channels -> items(s.subs.size) { i ->
                    val sub = s.subs[i]
                    Chip(onClick = { viewModel.loadChannel(sub.url, sub.name) },
                        label = { Text(sub.name, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        secondaryLabel = { Text("Tap to view videos") },
                        colors = ChipDefaults.gradientBackgroundChipColors(), modifier = Modifier.fillMaxWidth())
                }
                is UiState.History -> items(s.entries.size) { i ->
                    val e = s.entries[i]
                    Chip(onClick = {
                        ctx.startActivity(PlayerActivity.newIntent(ctx, e.url, e.title))
                    }, label = { Text(e.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                }
                is UiState.Downloads -> items(s.entries.size) { i ->
                    val e = s.entries[i]
                    Chip(onClick = {
                        ctx.startActivity(PlayerActivity.newIntent(ctx, "file://${e.filePath}", e.title))
                    }, label = { Text(e.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        secondaryLabel = { Text("\u25B6 Play offline") },
                        colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                }
                is UiState.Videos -> items(s.videos.size) { i ->
                    val v = s.videos[i]
                    Chip(onClick = {
                        if (v.type == ItemType.PLAYLIST) {
                            viewModel.loadPlaylist(v.videoUrl)
                        } else {
                            histMgr.add(v.videoUrl, v.title)
                            val allVids = s.videos.filter { it.type == ItemType.VIDEO }
                            if (mode == ScreenMode.PLAYLIST && allVids.size > 1) {
                                val idx = allVids.indexOf(v).coerceAtLeast(0)
                                ctx.startActivity(PlayerActivity.newPlaylistIntent(ctx,
                                    ArrayList(allVids.map { it.videoUrl }),
                                    ArrayList(allVids.map { it.title }), idx))
                            } else {
                                ctx.startActivity(PlayerActivity.newIntent(ctx, v.videoUrl, v.title))
                            }
                        }
                    }, label = { Text(v.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                        secondaryLabel = { Text("${v.channel} \u2022 ${v.durationText}",
                            maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        icon = {
                            AsyncImage(model = v.thumbnailUrl, contentDescription = null,
                                modifier = Modifier.size(32.dp).clip(RoundedCornerShape(4.dp)),
                                contentScale = ContentScale.Crop)
                        }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
    LaunchedEffect(mode) { listState.scrollToItem(0); focus.requestFocus() }
}
'@

# ============================================================
# 5. PlayerScreen.kt  (includes PlayerActivity)
# ============================================================
Emit "PlayerScreen.kt" @'
package com.tictube

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.ScalingLazyColumn
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.rememberScalingLazyListState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.ServiceList

// ─── Activity ─────────────────────────────────────────────────

class PlayerActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startService(Intent(this, PlaybackService::class.java))
        val url = intent.getStringExtra(EXTRA_VIDEO_URL).orEmpty()
        val title = intent.getStringExtra(EXTRA_VIDEO_TITLE).orEmpty()
        val plUrls = intent.getStringArrayListExtra(EXTRA_PL_URLS) ?: arrayListOf()
        val plTitles = intent.getStringArrayListExtra(EXTRA_PL_TITLES) ?: arrayListOf()
        val startIdx = intent.getIntExtra(EXTRA_START_IDX, 0)
        setContent { MaterialTheme {
            PlayerScreen(url, title, plUrls, plTitles, startIdx)
        }}
    }
    companion object {
        const val EXTRA_VIDEO_URL = "extra_video_url"
        const val EXTRA_VIDEO_TITLE = "extra_video_title"
        const val EXTRA_PL_URLS = "extra_pl_urls"
        const val EXTRA_PL_TITLES = "extra_pl_titles"
        const val EXTRA_START_IDX = "extra_start_idx"

        fun newIntent(ctx: Context, url: String, title: String) =
            Intent(ctx, PlayerActivity::class.java).apply {
                putExtra(EXTRA_VIDEO_URL, url); putExtra(EXTRA_VIDEO_TITLE, title) }

        fun newPlaylistIntent(ctx: Context, urls: ArrayList<String>,
                              titles: ArrayList<String>, startIdx: Int) =
            Intent(ctx, PlayerActivity::class.java).apply {
                putStringArrayListExtra(EXTRA_PL_URLS, urls)
                putStringArrayListExtra(EXTRA_PL_TITLES, titles)
                putExtra(EXTRA_START_IDX, startIdx) }
    }
}

// ─── Data ─────────────────────────────────────────────────────

private data class ExtractionResult(
    val streamUrl: String, val uploaderUrl: String, val uploaderName: String, val description: String)
data class CommentItem(val author: String, val text: String, val likes: Int, val date: String)
enum class DlState { IDLE, RUNNING, DONE, ERROR }

// ─── Extraction ───────────────────────────────────────────────

private suspend fun extract(ytUrl: String, q: SettingsManager.StreamQuality): ExtractionResult =
    withContext(Dispatchers.IO) {
        val ext = ServiceList.YouTube.getStreamExtractor(ytUrl); ext.fetchPage()
        val uUrl = ext.uploaderUrl.orEmpty()
        val uName = ext.uploaderName.orEmpty()
        val desc = try { ext.description?.content.orEmpty() } catch (_: Exception) { "" }
        val targetRes = when (q) {
            SettingsManager.StreamQuality.AUDIO_ONLY -> 0
            SettingsManager.StreamQuality.Q360P -> 360
            SettingsManager.StreamQuality.Q720P -> 720
        }
        var url: String? = null
        if (targetRes > 0) {
            val muxed = try { ext.videoStreams?.filter { it.isUrl } ?: emptyList() } catch (_: Exception) { emptyList() }
            url = muxed.minByOrNull { s ->
                val r = s.resolution?.replace(Regex("p.*"), "")?.toIntOrNull() ?: 999
                kotlin.math.abs(r - targetRes)
            }?.content
        }
        if (url.isNullOrBlank()) {
            val audio = try { ext.audioStreams?.filter { it.isUrl } ?: emptyList() } catch (_: Exception) { emptyList() }
            url = audio.maxByOrNull { it.averageBitrate }?.content
        }
        if (url.isNullOrBlank()) throw IllegalStateException("No playable streams")
        ExtractionResult(url, uUrl, uName, desc)
    }

private suspend fun loadComments(ytUrl: String): List<CommentItem> = withContext(Dispatchers.IO) {
    try {
        val ce = ServiceList.YouTube.getCommentsExtractor(ytUrl); ce.fetchPage()
        ce.initialPage.items.take(20).map { c ->
            CommentItem(c.uploaderName.orEmpty(),
                c.commentText?.content?.replace(Regex("<[^>]*>"), "").orEmpty(),
                c.likeCount, c.textualUploadDate.orEmpty())
        }
    } catch (e: Exception) { Log.w("Comments", "unavailable", e); emptyList() }
}

// ─── Main Composable ──────────────────────────────────────────

@Composable
fun PlayerScreen(
    videoUrl: String, videoTitle: String,
    plUrls: List<String> = emptyList(), plTitles: List<String> = emptyList(),
    startIdx: Int = 0
) {
    val ctx = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val audioMgr = remember { ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    val subMgr = remember { SubscriptionManager.getInstance(ctx.applicationContext) }
    val dlMgr = remember { DownloadManager.getInstance(ctx.applicationContext) }
    val histMgr = remember { HistoryManager.getInstance(ctx.applicationContext) }
    val settMgr = remember { SettingsManager.getInstance(ctx.applicationContext) }
    val scope = rememberCoroutineScope()

    val isPlaylist = plUrls.isNotEmpty()
    var curIdx by remember { mutableStateOf(startIdx) }
    val curUrl = if (isPlaylist) plUrls.getOrElse(curIdx) { videoUrl } else videoUrl
    val curTitle = if (isPlaylist) plTitles.getOrElse(curIdx) { videoTitle } else videoTitle
    val isLocal = curUrl.startsWith("file://") || curUrl.startsWith("/")
    val pageCount = if (isLocal) 1 else 2

    var showCtrls by remember { mutableStateOf(false) }
    var isPlaying by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(true) }
    var errorMsg by remember { mutableStateOf<String?>(null) }
    var player by remember { mutableStateOf(PlaybackService.player) }
    var upUrl by remember { mutableStateOf("") }
    var upName by remember { mutableStateOf("") }
    var isSub by remember { mutableStateOf(false) }
    var desc by remember { mutableStateOf("") }
    var comments by remember { mutableStateOf<List<CommentItem>>(emptyList()) }
    var extractedUrl by remember { mutableStateOf("") }
    var dlState by remember { mutableStateOf(DlState.IDLE) }

    val volFocus = remember { FocusRequester() }
    val infoFocus = remember { FocusRequester() }
    val pagerState = rememberPagerState(pageCount = { pageCount })

    // Poll for player
    LaunchedEffect(Unit) { while (player == null) { delay(100); player = PlaybackService.player } }

    // Extract & play
    LaunchedEffect(player, curUrl) {
        val p = player ?: return@LaunchedEffect
        if (curUrl.isEmpty()) return@LaunchedEffect
        isLoading = true; errorMsg = null; dlState = DlState.IDLE; desc = ""; comments = emptyList()
        try {
            if (isLocal) {
                p.setMediaItem(MediaItem.fromUri(curUrl)); p.prepare(); p.playWhenReady = true
                isLoading = false; showCtrls = true
            } else {
                val result = extract(curUrl, settMgr.getQuality())
                extractedUrl = result.streamUrl
                upUrl = result.uploaderUrl; upName = result.uploaderName
                desc = result.description.replace(Regex("<[^>]*>"), "").trim()
                isSub = subMgr.isSubscribed(result.uploaderUrl)
                histMgr.add(curUrl, curTitle)
                p.setMediaItem(MediaItem.fromUri(result.streamUrl)); p.prepare(); p.playWhenReady = true
                isLoading = false; showCtrls = true
            }
        } catch (e: Exception) {
            Log.e("Player", "extract", e); isLoading = false
            errorMsg = e.localizedMessage ?: "Could not load video"
        }
    }

    // Load comments lazily
    LaunchedEffect(curUrl) {
        if (isLocal || curUrl.isEmpty()) return@LaunchedEffect
        comments = loadComments(curUrl)
    }

    // Auto-hide controls
    LaunchedEffect(showCtrls) { if (showCtrls) { delay(5000); showCtrls = false } }

    // Player listener
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(p: Boolean) { isPlaying = p }
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED && isPlaylist && curIdx < plUrls.size - 1) curIdx++
            }
        }
        player?.addListener(listener)
        onDispose { player?.removeListener(listener) }
    }

    // Lifecycle
    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, ev ->
            if (ev == Lifecycle.Event.ON_START) player?.let { isPlaying = it.isPlaying }
        }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    // Focus per page
    LaunchedEffect(pagerState.currentPage) {
        try {
            if (pagerState.currentPage == 0) volFocus.requestFocus() else infoFocus.requestFocus()
        } catch (_: Exception) {}
    }

    // ── UI ────────────────────────────────────────────────────
    Box(Modifier.fillMaxSize().clip(CircleShape).background(Color.Black)) {
        VerticalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
            when (page) {
                0 -> PlayerPage(
                    player = player, isLoading = isLoading, errorMsg = errorMsg,
                    isPlaying = isPlaying, showCtrls = showCtrls,
                    curTitle = curTitle, upUrl = upUrl, upName = upName, isSub = isSub,
                    extractedUrl = extractedUrl, dlState = dlState,
                    isLocal = isLocal, isPlaylist = isPlaylist,
                    curIdx = curIdx, totalTracks = plUrls.size,
                    audioMgr = audioMgr, focusReq = volFocus,
                    onTap = { showCtrls = !showCtrls },
                    onPlayPause = { player?.let { if (it.isPlaying) it.pause() else it.play() } },
                    onSub = {
                        if (isSub) subMgr.unsubscribe(upUrl) else subMgr.subscribe(upUrl, upName)
                        isSub = !isSub; showCtrls = true
                    },
                    onDownload = {
                        if (extractedUrl.isNotBlank() && dlState != DlState.RUNNING) {
                            dlState = DlState.RUNNING
                            scope.launch {
                                try { dlMgr.download(extractedUrl, curTitle); dlState = DlState.DONE }
                                catch (e: Exception) { Log.e("DL", "fail", e); dlState = DlState.ERROR }
                            }
                        }
                        showCtrls = true
                    },
                    onSkipNext = { if (isPlaylist && curIdx < plUrls.size - 1) curIdx++ },
                    onFinish = { (ctx as? ComponentActivity)?.finish() }
                )
                1 -> InfoPage(curTitle, desc, comments, infoFocus)
            }
        }

        // Page indicator
        if (pageCount > 1) {
            Column(Modifier.align(Alignment.CenterEnd).padding(end = 4.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp)) {
                repeat(pageCount) { idx ->
                    Box(Modifier.size(4.dp).clip(CircleShape)
                        .background(if (idx == pagerState.currentPage) Color.White else Color.Gray.copy(0.4f)))
                }
            }
        }
    }
}

// ─── Page 0: Player ───────────────────────────────────────────

@Composable
private fun PlayerPage(
    player: androidx.media3.exoplayer.ExoPlayer?, isLoading: Boolean, errorMsg: String?,
    isPlaying: Boolean, showCtrls: Boolean, curTitle: String,
    upUrl: String, upName: String, isSub: Boolean,
    extractedUrl: String, dlState: DlState, isLocal: Boolean,
    isPlaylist: Boolean, curIdx: Int, totalTracks: Int,
    audioMgr: AudioManager, focusReq: FocusRequester,
    onTap: () -> Unit, onPlayPause: () -> Unit, onSub: () -> Unit,
    onDownload: () -> Unit, onSkipNext: () -> Unit, onFinish: () -> Unit
) {
    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black)
            .onRotaryScrollEvent { ev ->
                audioMgr.adjustStreamVolume(AudioManager.STREAM_MUSIC,
                    if (ev.verticalScrollPixels > 0f) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                    AudioManager.FLAG_SHOW_UI); true
            }.focusRequester(focusReq).focusable().clickable { onTap() },
        contentAlignment = Alignment.Center
    ) {
        // Video surface
        if (!isLoading && errorMsg == null) {
            player?.let { exo ->
                AndroidView(factory = { c -> PlayerView(c).apply { this.player = exo; useController = false; setKeepScreenOn(true) } },
                    update = { it.player = player }, modifier = Modifier.fillMaxSize())
            }
        }
        // Loading
        if (isLoading) Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Extracting stream\u2026", color = Color.White, style = MaterialTheme.typography.body1)
            Spacer(Modifier.height(4.dp))
            Text(curTitle, color = Color.Gray, style = MaterialTheme.typography.caption3,
                maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
        }
        // Error
        if (errorMsg != null) Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("\u26A0 Error", color = Color(0xFFFF6B6B), style = MaterialTheme.typography.title3)
            Spacer(Modifier.height(4.dp))
            Text(errorMsg, color = Color.White, style = MaterialTheme.typography.caption3,
                maxLines = 3, textAlign = TextAlign.Center)
            Spacer(Modifier.height(8.dp))
            Chip(onClick = onFinish, label = { Text("Back") }, colors = ChipDefaults.secondaryChipColors())
        }
        // Controls overlay
        if (showCtrls && !isLoading && errorMsg == null && player != null) {
            Column(horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                // Playlist track info
                if (isPlaylist) Text("${curIdx + 1}/$totalTracks",
                    color = Color.White.copy(0.7f), style = MaterialTheme.typography.caption3)
                // Play/Pause
                Button(onClick = onPlayPause, modifier = Modifier.size(ButtonDefaults.LargeButtonSize),
                    colors = ButtonDefaults.buttonColors(backgroundColor = Color.Black.copy(alpha = 0.55f))
                ) { Text(if (isPlaying) "\u23F8" else "\u25B6", style = MaterialTheme.typography.title1, color = Color.White) }

                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    // Subscribe
                    if (upUrl.isNotEmpty() && !isLocal) {
                        CompactChip(onClick = onSub, label = {
                            Text(if (isSub) "\u2764" else "\u2661", maxLines = 1)
                        }, colors = if (isSub) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors())
                    }
                    // Download
                    if (!isLocal && extractedUrl.isNotBlank()) {
                        CompactChip(onClick = onDownload, label = {
                            Text(when (dlState) {
                                DlState.IDLE -> "\u2B07"
                                DlState.RUNNING -> "\u231B"
                                DlState.DONE -> "\u2714"
                                DlState.ERROR -> "\u26A0"
                            }, maxLines = 1)
                        }, colors = if (dlState == DlState.DONE) ChipDefaults.primaryChipColors()
                            else ChipDefaults.secondaryChipColors())
                    }
                    // Skip next
                    if (isPlaylist) {
                        CompactChip(onClick = onSkipNext, label = { Text("\u23ED", maxLines = 1) },
                            colors = ChipDefaults.secondaryChipColors())
                    }
                }
            }
        }
    }
}

// ─── Page 1: Info ─────────────────────────────────────────────

@Composable
private fun InfoPage(title: String, desc: String, comments: List<CommentItem>, focusReq: FocusRequester) {
    val listState = rememberScalingLazyListState()
    Scaffold(positionIndicator = { PositionIndicator(scalingLazyListState = listState) }) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize()
                .rotaryScrollable(behavior = RotaryScrollableDefaults.behavior(listState), focusRequester = focusReq)
                .focusRequester(focusReq).focusable()
        ) {
            item { Text(title, style = MaterialTheme.typography.title3, color = Color.White,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)) }
            if (desc.isNotBlank()) {
                item { Spacer(Modifier.height(8.dp)) }
                item { Text(desc.take(1000), style = MaterialTheme.typography.body2, color = Color.LightGray,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp)) }
            }
            item { Spacer(Modifier.height(12.dp)) }
            item { Text("\uD83D\uDCAC Comments (${comments.size})", style = MaterialTheme.typography.title3,
                color = Color.White, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)) }
            if (comments.isEmpty()) {
                item { Text("No comments available", color = Color.Gray,
                    style = MaterialTheme.typography.body2, modifier = Modifier.padding(horizontal = 12.dp)) }
            } else {
                items(comments.size) { i ->
                    val c = comments[i]
                    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
                        Text(c.author, style = MaterialTheme.typography.caption1, color = Color.Cyan, maxLines = 1)
                        Text(c.text.take(300), style = MaterialTheme.typography.body2, color = Color.White,
                            maxLines = 6, overflow = TextOverflow.Ellipsis)
                        Text("\u2764 ${c.likes}  \u2022  ${c.date}", style = MaterialTheme.typography.caption3,
                            color = Color.Gray)
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}
'@

# ============================================================
# 6. MainActivity.kt  (OVERWRITE - simplified, no callback)
# ============================================================
Emit "MainActivity.kt" @'
package com.tictube

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { TicTubeWearApp() }
    }
}

@androidx.compose.runtime.Composable
fun TicTubeWearApp() {
    val navController = rememberSwipeDismissableNavController()
    MaterialTheme {
        SwipeDismissableNavHost(navController = navController, startDestination = "main") {
            composable("main") { MainScreen() }
        }
    }
}
'@

# ============================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " Phase 5 complete - 6 files generated            " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "What's new:" -ForegroundColor White
Write-Host "  1. Watch History     - HistoryManager + History chip in feed" -ForegroundColor Gray
Write-Host "  2. Quality Selection - SettingsManager + cycling CompactChip" -ForegroundColor Gray
Write-Host "  3. Offline Downloads - DownloadManager + Download button in player" -ForegroundColor Gray
Write-Host "  4. Playlist Support  - PlaylistExtractor + sequential playback" -ForegroundColor Gray
Write-Host "  5. Comments & Desc   - VerticalPager swipe-up info page" -ForegroundColor Gray
Write-Host ""
Write-Host "Next: run '.\build_apk.ps1' to compile." -ForegroundColor Yellow
