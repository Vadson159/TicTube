# fix_phase8.ps1
# TicTube Wear OS - Phase 8 Hotfix & Infinite Mixed Feed Feature
# Run from project root: S:\_Vibe_Coding\TicTube\WearApp
#
# Overwrites 1 file:
#   1. MainScreen.kt

$ErrorActionPreference = "Stop"
$basePath  = Join-Path $PSScriptRoot "app\src\main\java\com\tictube"
if (-not (Test-Path $basePath)) { New-Item -ItemType Directory -Force -Path $basePath | Out-Null }
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Emit($dir, $name, $content) {
    $p = Join-Path $dir $name
    [System.IO.File]::WriteAllText($p, $content, $utf8)
    Write-Host "  [OK] $name" -ForegroundColor Green
}

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " TicTube - Fixes + Mixed Infinite Feed (Tags)        " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

Emit $basePath "MainScreen.kt" @'
package com.tictube

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.speech.RecognizerIntent
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
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
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import androidx.wear.compose.material.rememberScalingLazyListState
import coil.compose.AsyncImage
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.InfoItem
import org.schabi.newpipe.extractor.ListExtractor
import org.schabi.newpipe.extractor.Page
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.playlist.PlaylistInfoItem
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.StreamType

// ─── Data ─────────────────────────────────────────────────────

enum class ItemType { VIDEO, PLAYLIST }

data class VideoItem(
    val id: String,
    val title: String,
    val channel: String,
    val durationText: String,
    val thumbnailUrl: String = "",
    val videoUrl: String = "",
    val type: ItemType = ItemType.VIDEO,
    val isLive: Boolean = false
)

sealed interface UiState {
    object Loading : UiState
    data class Videos(val videos: List<VideoItem>) : UiState
    data class Channels(val subs: List<Subscription>) : UiState
    data class History(val entries: List<HistoryEntry>) : UiState
    data class Downloads(val entries: List<DownloadEntry>) : UiState
    data class Error(val message: String) : UiState
}

enum class ScreenMode { FEED, SUBSCRIPTIONS, CHANNEL, HISTORY, DOWNLOADS, PLAYLIST, TAGS }

// ─── ViewModel ────────────────────────────────────────────────

class MainViewModel(app: Application) : AndroidViewModel(app) {

    companion object { 
        private const val TAG = "MainVM"
        private const val MAX = 20 
        val AVAILABLE_TAGS = listOf("Tech", "Business", "Travel", "Science", "Music", "Gaming", "News", "Sports", "Podcasts", "Comedy", "Cars", "Fitness")
    }

    private val subMgr = SubscriptionManager.getInstance(app)
    private val histMgr = HistoryManager.getInstance(app)
    private val dlMgr = DownloadManager.getInstance(app)
    val settingsMgr = SettingsManager.getInstance(app)

    private val prefs = app.getSharedPreferences("tictube_tags", Context.MODE_PRIVATE)

    private val _mode = MutableStateFlow(ScreenMode.FEED)
    val mode: StateFlow<ScreenMode> = _mode.asStateFlow()
    private val _ui = MutableStateFlow<UiState>(UiState.Loading)
    val ui: StateFlow<UiState> = _ui.asStateFlow()
    private val _header = MutableStateFlow("")
    val header: StateFlow<String> = _header.asStateFlow()
    private val _quality = MutableStateFlow(settingsMgr.getQuality())
    val quality: StateFlow<SettingsManager.StreamQuality> = _quality.asStateFlow()

    private val _activeTags = MutableStateFlow(
        prefs.getStringSet("tags", AVAILABLE_TAGS.toSet())?.toList() ?: AVAILABLE_TAGS
    )
    val activeTags: StateFlow<List<String>> = _activeTags.asStateFlow()

    private var currentExtractor: ListExtractor<InfoItem>? = null
    private var nextPageUrl: Page? = null
    private var isLoadingMore = false
    private var lastQuery = ""
    private var isMixedFeed = true

    // Tracking for mixed feed pages to avoid duplicates
    private val seenVideoIds = mutableSetOf<String>()
    private val tagPages = mutableMapOf<String, Page?>()
    private val tagExtractors = mutableMapOf<String, ListExtractor<InfoItem>>()

    init { loadMixedFeed(clear = true) }

    fun toggleTag(tag: String) {
        val current = _activeTags.value.toMutableSet()
        if (current.contains(tag) && current.size > 1) {
            current.remove(tag)
        } else {
            current.add(tag)
        }
        prefs.edit().putStringSet("tags", current).apply()
        _activeTags.value = current.toList()
    }

    fun showTags() {
        _mode.value = ScreenMode.TAGS
        _header.value = "Feed Topics"
        _ui.value = UiState.Loading
    }

    fun loadMixedFeed(clear: Boolean = true) {
        if (isLoadingMore) return
        isLoadingMore = true
        isMixedFeed = true
        lastQuery = ""

        if (clear) {
            _mode.value = ScreenMode.FEED
            _header.value = "\uD83C\uDFB2 Mixed Feed"
            seenVideoIds.clear()
            tagPages.clear()
            tagExtractors.clear()
            _ui.value = UiState.Loading
        }

        viewModelScope.launch {
            try {
                val tags = _activeTags.value
                val randomTag = if (tags.isNotEmpty()) tags.random() else "Tech"

                val vids = withContext(Dispatchers.IO) {
                    if (!tagExtractors.containsKey(randomTag)) {
                        val ext = ServiceList.YouTube.getSearchExtractor(randomTag)
                        @Suppress("UNCHECKED_CAST")
                        tagExtractors[randomTag] = ext as ListExtractor<InfoItem>
                        ext.fetchPage()
                        tagPages[randomTag] = ext.initialPage.nextPage
                        ext.initialPage.items.mapNotNull { it.toItem() }
                    } else {
                        val ext = tagExtractors[randomTag]!!
                        val nextPage = tagPages[randomTag]
                        if (nextPage != null) {
                            val page = ext.getPage(nextPage)
                            tagPages[randomTag] = page.nextPage
                            page.items.mapNotNull { it.toItem() }
                        } else emptyList()
                    }
                }

                val uniqueVids = vids.filter { it.type == ItemType.VIDEO && seenVideoIds.add(it.id) }

                val currentState = _ui.value
                if (clear || currentState !is UiState.Videos) {
                    _ui.value = if (uniqueVids.isEmpty()) UiState.Error("No videos found. Pull/Scroll to refresh.") else UiState.Videos(uniqueVids)
                } else {
                    _ui.value = UiState.Videos(currentState.videos + uniqueVids)
                }
            } catch (e: Exception) {
                if (clear) {
                    Log.e(TAG, "mixed feed error", e)
                    _ui.value = UiState.Error(e.localizedMessage ?: "Failed to load feed")
                }
            } finally {
                isLoadingMore = false
            }
        }
    }

    fun search(query: String) {
        if (query.isBlank()) { loadMixedFeed(true); return }
        lastQuery = query
        isMixedFeed = false
        _mode.value = ScreenMode.FEED
        _header.value = "\uD83D\uDD0D $query"
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val ext = ServiceList.YouTube.getSearchExtractor(query)
                    @Suppress("UNCHECKED_CAST")
                    currentExtractor = ext as? ListExtractor<InfoItem>
                    ext.fetchPage()
                    nextPageUrl = ext.initialPage.nextPage
                    ext.initialPage.items.mapNotNull { it.toItem() }
                }
                _ui.value = if (vids.isEmpty()) UiState.Error("No results") else UiState.Videos(vids)
            } catch (e: Exception) {
                Log.e(TAG, "search", e); _ui.value = UiState.Error(e.localizedMessage ?: "Search failed")
            }
        }
    }

    fun loadMore() {
        if (isMixedFeed) {
            loadMixedFeed(clear = false)
            return
        }

        if (isLoadingMore || nextPageUrl == null) return
        val ext = currentExtractor ?: return
        val currentState = _ui.value
        if (currentState !is UiState.Videos) return

        isLoadingMore = true
        viewModelScope.launch {
            try {
                val moreVids = withContext(Dispatchers.IO) {
                    val page = ext.getPage(nextPageUrl)
                    nextPageUrl = page.nextPage
                    page.items.mapNotNull { it.toItem() }
                }
                _ui.value = UiState.Videos(currentState.videos + moreVids)
            } catch (e: Exception) {
                Log.e(TAG, "loadMore", e)
            } finally {
                isLoadingMore = false
            }
        }
    }

    fun deleteDownload(fileName: String) {
        viewModelScope.launch(Dispatchers.IO) {
            dlMgr.delete(fileName)
            val d = dlMgr.getAll()
            _ui.value = if (d.isEmpty()) UiState.Error("No downloads left.") else UiState.Downloads(d)
        }
    }

    fun showSubscriptions() {
        _mode.value = ScreenMode.SUBSCRIPTIONS; _header.value = "\u2764\uFE0F My Channels"
        val s = subMgr.getAll()
        _ui.value = if (s.isEmpty()) UiState.Error("No subscriptions yet.") else UiState.Channels(s)
    }

    fun showHistory() {
        _mode.value = ScreenMode.HISTORY; _header.value = "\uD83D\uDD52 History"
        val h = histMgr.getAll()
        _ui.value = if (h.isEmpty()) UiState.Error("No history yet.") else UiState.History(h)
    }

    fun showDownloads() {
        _mode.value = ScreenMode.DOWNLOADS; _header.value = "\uD83D\uDCBE Downloads"
        val d = dlMgr.getAll()
        _ui.value = if (d.isEmpty()) UiState.Error("No downloads yet.") else UiState.Downloads(d)
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
                    val te = ServiceList.YouTube.getChannelTabExtractor(tab)
                    @Suppress("UNCHECKED_CAST")
                    currentExtractor = te as? ListExtractor<InfoItem>
                    te.fetchPage()
                    nextPageUrl = te.initialPage.nextPage
                    te.initialPage.items.filterIsInstance<StreamInfoItem>().map { it.toVideoItem() }
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
                    currentExtractor = null
                    nextPageUrl = null
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
        ScreenMode.TAGS -> loadMixedFeed(true)
        else -> if (lastQuery.isNotBlank()) search(lastQuery) else loadMixedFeed(true)
    }}

    fun retry() { when (_mode.value) {
        ScreenMode.FEED -> if (lastQuery.isNotBlank()) search(lastQuery) else loadMixedFeed(true)
        ScreenMode.SUBSCRIPTIONS -> showSubscriptions()
        ScreenMode.HISTORY -> showHistory()
        ScreenMode.DOWNLOADS -> showDownloads()
        ScreenMode.TAGS -> showTags()
        else -> loadMixedFeed(true)
    }}

    private fun InfoItem.toItem(): VideoItem? = when (this) {
        is StreamInfoItem -> toVideoItem()
        is PlaylistInfoItem -> VideoItem(url, "\uD83C\uDFB5 $name", uploaderName.orEmpty(),
            "${streamCount} videos", thumbnails.firstOrNull()?.url.orEmpty(), url, ItemType.PLAYLIST)
        else -> null
    }

    private fun StreamInfoItem.toVideoItem(): VideoItem {
        val live = streamType == StreamType.LIVE_STREAM ||
                   streamType == StreamType.AUDIO_LIVE_STREAM
        return VideoItem(url, name, uploaderName.orEmpty(),
            if (live) "LIVE" else fmtDur(duration),
            thumbnails.firstOrNull()?.url.orEmpty(), url, ItemType.VIDEO, isLive = live)
    }
}

private fun fmtDur(s: Long): String {
    if (s < 0) return "LIVE"
    val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
    return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%d:%02d", m, sec)
}

// ─── Composable ───────────────────────────────────────────────

@OptIn(ExperimentalPermissionsApi::class)
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
    val subMgr = remember { SubscriptionManager.getInstance(ctx.applicationContext) }
    val scope = rememberCoroutineScope()
    val storagePerm = rememberPermissionState(Manifest.permission.READ_EXTERNAL_STORAGE)

    // Infinite scroll detection
    val isAtBottom by remember {
        derivedStateOf {
            val layoutInfo = listState.layoutInfo
            val totalItems = layoutInfo.totalItemsCount
            val lastVisibleItem = layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            lastVisibleItem >= totalItems - 3 && totalItems > 0
        }
    }

    LaunchedEffect(isAtBottom) {
        if (isAtBottom && (mode == ScreenMode.FEED || mode == ScreenMode.CHANNEL)) {
            viewModel.loadMore()
        }
    }

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
                .focusRequester(focus)
                .focusable()
                .rotaryScrollable(behavior = RotaryScrollableDefaults.behavior(listState), focusRequester = focus)
        ) {
            
            // ── Tags Mode (Topic Selection) ──
            if (mode == ScreenMode.TAGS) {
                item { Chip(onClick = { viewModel.loadMixedFeed(true) }, label = { Text("\u2B05 Back & Refresh") }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                item { Text("Select Feed Topics", style = MaterialTheme.typography.caption1, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) }
                
                val activeTags by viewModel.activeTags.collectAsState()
                items(MainViewModel.AVAILABLE_TAGS.size) { i ->
                    val tag = MainViewModel.AVAILABLE_TAGS[i]
                    val isSelected = activeTags.contains(tag)
                    Chip(
                        onClick = { viewModel.toggleTag(tag) },
                        label = { Text(tag) },
                        secondaryLabel = { Text(if (isSelected) "Enabled" else "Disabled", color = if(isSelected) Color.Green else Color.Gray) },
                        colors = if (isSelected) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors(),
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            } 
            else {
                // ── Normal Feed Modes ──
                
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
                    item { Chip(onClick = { viewModel.showTags() },
                        label = { Text("\uD83C\uDFF7\uFE0F Feed Topics") },
                        colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
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

                // ── Import CSV chip ──
                if (mode == ScreenMode.SUBSCRIPTIONS) {
                    item {
                        Chip(onClick = {
                            if (!storagePerm.status.isGranted) {
                                storagePerm.launchPermissionRequest()
                            }
                            scope.launch {
                                val result = withContext(Dispatchers.IO) { CsvImporter.import(ctx, subMgr) }
                                if (result.isSuccess) {
                                    Toast.makeText(ctx, "\u2705 Imported ${result.count} channels!", Toast.LENGTH_SHORT).show()
                                    viewModel.showSubscriptions()
                                } else {
                                    Toast.makeText(ctx, result.error ?: "Import failed", Toast.LENGTH_LONG).show()
                                }
                            }
                        }, label = { Text("\uD83D\uDCE5 Import CSV") },
                            colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                    }
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
                                maxLines = 6, overflow = TextOverflow.Ellipsis)
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
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Chip(onClick = {
                                ctx.startActivity(PlayerActivity.newIntent(ctx, "file://${e.filePath}", e.title))
                            }, label = { Text(e.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                                secondaryLabel = { Text("\u25B6 Play offline") },
                                colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.weight(1f))
                            
                            Button(onClick = { viewModel.deleteDownload(e.fileName) },
                                modifier = Modifier.size(52.dp),
                                colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFB00020))
                            ) { Text("\uD83D\uDDD1\uFE0F", color = Color.White) }
                        }
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
                            secondaryLabel = {
                                Text(
                                    text = if (v.isLive) "\uD83D\uDD34 LIVE \u2022 ${v.channel}"
                                           else "${v.channel} \u2022 ${v.durationText}",
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                            },
                            icon = {
                                AsyncImage(model = v.thumbnailUrl, contentDescription = null,
                                    modifier = Modifier.size(32.dp).clip(RoundedCornerShape(4.dp)),
                                    contentScale = ContentScale.Crop)
                            }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        }
    }

    // Force focus when mode or UI state changes
    LaunchedEffect(mode, ui) {
        val firstIdx = listState.layoutInfo.visibleItemsInfo.firstOrNull()?.index ?: 0
        if (mode == ScreenMode.TAGS || ui !is UiState.Videos || firstIdx == 0) {
            focus.requestFocus()
        }
    }
}
'@

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " Fixes applied! New Mixed Feed (Tags) added!         " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "What changed:" -ForegroundColor White
Write-Host "  1. Added 'import androidx.compose.ui.graphics.Color'." -ForegroundColor Gray
Write-Host "  2. Fixed rotaryScrollable: passed 'focusRequester = focus'." -ForegroundColor Gray
Write-Host "  3. Fixed 'firstVisibleItemIndex' by using layoutInfo." -ForegroundColor Gray
Write-Host "  4. Added 'Feed Topics' chip: customize infinite feed." -ForegroundColor Gray
Write-Host "  5. Infinite feed randomly samples your selected tags!" -ForegroundColor Gray
Write-Host ""
Write-Host "Next: run '.\build_apk.ps1' to compile." -ForegroundColor Yellow
