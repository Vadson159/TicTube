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
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Scope
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
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.TextStyle
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.List
import androidx.compose.material.icons.rounded.FileDownload
import androidx.compose.material.icons.rounded.Close
import androidx.wear.compose.material.Icon
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
import androidx.compose.foundation.focusable
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

enum class ItemType { VIDEO, PLAYLIST }

data class VideoItem(
    val id: String, val title: String, val channel: String,
    val durationText: String, val thumbnailUrl: String = "",
    val videoUrl: String = "", val type: ItemType = ItemType.VIDEO,
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

enum class ScreenMode { FEED, SUBSCRIPTIONS, CHANNEL, HISTORY, DOWNLOADS, PLAYLIST, TAGS, SHORTS }

class MainViewModel(app: Application) : AndroidViewModel(app) {
    companion object { 
        private const val TAG = "MainVM"
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

    private val authMgr = AuthManager.getInstance(app)
    private val ytApi = YouTubeApi.getInstance(app)
    private var subChannels = listOf<Subscription>()

    private val _activeTags = MutableStateFlow(
        prefs.getStringSet("tags", AVAILABLE_TAGS.toSet())?.toList() ?: AVAILABLE_TAGS
    )
    val activeTags: StateFlow<List<String>> = _activeTags.asStateFlow()

    private var currentExtractor: ListExtractor<InfoItem>? = null
    private var nextPageUrl: Page? = null
    private var isLoadingMore = false
    private var lastQuery = ""
    private var isMixedFeed = true

    private val seenVideoIds = mutableSetOf<String>()
    private val seenShortIds = mutableSetOf<String>()
    private val tagPages = mutableMapOf<String, Page?>()
    private val tagExtractors = mutableMapOf<String, ListExtractor<InfoItem>>()
    private val shortsQueries = listOf("#shorts", "shorts", "youtube shorts", "shorts viral", "shorts tech", "shorts music", "shorts comedy")
    private var shortsQueryIndex = 0

    init { loadMixedFeed(clear = true) }

    fun toggleTag(tag: String) {
        val current = _activeTags.value.toMutableSet()
        if (current.contains(tag) && current.size > 1) current.remove(tag) else current.add(tag)
        prefs.edit().putStringSet("tags", current).apply()
        _activeTags.value = current.toList()
    }

    fun showTags() { _mode.value = ScreenMode.TAGS; _header.value = "Feed Topics"; _ui.value = UiState.Loading }

    fun loadMixedFeed(clear: Boolean = true) {
        if (isLoadingMore && _mode.value == ScreenMode.FEED) return
        isLoadingMore = true; isMixedFeed = true; lastQuery = ""
        if (clear) { _mode.value = ScreenMode.FEED; _header.value = "\uD83C\uDFB2 Mixed Feed"; seenVideoIds.clear(); tagPages.clear(); tagExtractors.clear(); _ui.value = UiState.Loading }
        viewModelScope.launch {
            try {
                val vids = withContext(Dispatchers.IO) {
                    val list = mutableListOf<VideoItem>()
                    val token = authMgr.getAccessToken()
                    if (token != null) {
                        if (subChannels.isEmpty()) subChannels = ytApi.getSubscriptions()
                        if (subChannels.isNotEmpty()) {
                            val randomCh = subChannels.shuffled().take(2).map { it.url.substringAfterLast("/") }
                            val playlists = ytApi.getUploadPlaylists(randomCh)
                            playlists.forEach { pl -> list.addAll(ytApi.getLatestVideos(pl, 4)) }
                        }
                    }
                    
                    val tags = _activeTags.value.ifEmpty { listOf("Tech") }.shuffled()
                    tags.take(4).forEach { tag ->
                        list.addAll(loadTagPage(tag).take(8))
                    }
                    list
                }
                
                if (_mode.value != ScreenMode.FEED || !isMixedFeed) return@launch
                val uniqueVids = vids.filter { it.type == ItemType.VIDEO && seenVideoIds.add(it.id) }.shuffled()
                val currentState = _ui.value
                if (clear || currentState !is UiState.Videos) _ui.value = if (uniqueVids.isEmpty()) UiState.Error("No videos found.") else UiState.Videos(uniqueVids)
                else _ui.value = UiState.Videos(currentState.videos + uniqueVids)
            } catch (e: Exception) {
                if (clear && _mode.value == ScreenMode.FEED && isMixedFeed) {
                    _ui.value = UiState.Error(e.localizedMessage ?: "Failed to load feed")
                }
            } finally { isLoadingMore = false }
        }
    }

    fun search(query: String) {
        if (query.isBlank()) { loadMixedFeed(true); return }
        lastQuery = query; isMixedFeed = false; _mode.value = ScreenMode.FEED; _header.value = "\uD83D\uDD0D $query"
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val ext = ServiceList.YouTube.getSearchExtractor(query)
                    @Suppress("UNCHECKED_CAST")
                    currentExtractor = ext as? ListExtractor<InfoItem>
                    ext.fetchPage(); nextPageUrl = ext.initialPage.nextPage; ext.initialPage.items.mapNotNull { it.toItem() }
                }
                if (_mode.value == ScreenMode.FEED && lastQuery == query) {
                    _ui.value = if (vids.isEmpty()) UiState.Error("No results") else UiState.Videos(vids)
                }
            } catch (e: Exception) {
                if (_mode.value == ScreenMode.FEED && lastQuery == query) {
                    _ui.value = UiState.Error(e.localizedMessage ?: "Search failed")
                }
            }
        }
    }

    fun loadMore() {
        val mode = _mode.value
        if (mode == ScreenMode.FEED && isMixedFeed) { loadMixedFeed(clear = false); return }
        if (mode == ScreenMode.SHORTS) { loadMoreShorts(); return }
        if (mode != ScreenMode.FEED && mode != ScreenMode.CHANNEL) return
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
                    var items = page.items.mapNotNull { it.toItem() }
                    items
                }
                if (_mode.value == mode) _ui.value = UiState.Videos(currentState.videos + moreVids)
            } catch (e: Exception) { } finally { isLoadingMore = false }
        }
    }

    private fun loadMoreShorts() {
        if (isLoadingMore) return
        val currentState = _ui.value as? UiState.Videos ?: return
        isLoadingMore = true
        viewModelScope.launch {
            try {
                val moreVids = withContext(Dispatchers.IO) { fetchShortsBatch(targetCount = 8) }
                if (_mode.value == ScreenMode.SHORTS && moreVids.isNotEmpty()) {
                    _ui.value = UiState.Videos(currentState.videos + moreVids)
                }
            } catch (e: Exception) { } finally { isLoadingMore = false }
        }
    }

    fun deleteDownload(fileName: String) { viewModelScope.launch(Dispatchers.IO) { dlMgr.delete(fileName); val d = dlMgr.getAll(); _ui.value = if (d.isEmpty()) UiState.Error("No downloads left.") else UiState.Downloads(d) } }
    fun showSubscriptions() { 
        _mode.value = ScreenMode.SUBSCRIPTIONS; _header.value = "\u2764\uFE0F My Channels"; _ui.value = UiState.Loading
        viewModelScope.launch {
            try {
                val s = withContext(Dispatchers.IO) {
                    val localSubs = subMgr.getAll()
                    val apiSubs = if (settingsMgr.accountName.isNotBlank()) ytApi.getSubscriptions() else emptyList()
                    if (apiSubs.isNotEmpty()) {
                        apiSubs.forEach { subMgr.subscribe(it.url, it.name) }
                    }
                    mergeSubscriptions(localSubs, apiSubs)
                }
                if (_mode.value == ScreenMode.SUBSCRIPTIONS) {
                    subChannels = s
                    val syncError = ytApi.lastError ?: authMgr.lastError
                    _ui.value = if (s.isEmpty()) {
                        UiState.Error(syncError ?: "No subscriptions yet.")
                    } else {
                        UiState.Channels(s)
                    }
                }
            } catch (e: Exception) {
                if (_mode.value == ScreenMode.SUBSCRIPTIONS) _ui.value = UiState.Error("Failed to load subscriptions")
            }
        }
    }
    fun showHistory() { _mode.value = ScreenMode.HISTORY; _header.value = "\uD83D\uDD52 History"; val h = histMgr.getAll(); _ui.value = if (h.isEmpty()) UiState.Error("No history yet.") else UiState.History(h) }
    fun showDownloads() { _mode.value = ScreenMode.DOWNLOADS; _header.value = "\uD83D\uDCBE Downloads"; val d = dlMgr.getAll(); _ui.value = if (d.isEmpty()) UiState.Error("No downloads yet.") else UiState.Downloads(d) }
    fun cycleQuality() { _quality.value = settingsMgr.cycleQuality() }
    
    fun showShorts() {
        if (isLoadingMore && _mode.value == ScreenMode.SHORTS) return
        isLoadingMore = true; isMixedFeed = false; lastQuery = ""
        _mode.value = ScreenMode.SHORTS; _header.value = "\u26A1 Shorts"; currentExtractor = null; nextPageUrl = null; seenShortIds.clear(); shortsQueryIndex = 0; _ui.value = UiState.Loading
        viewModelScope.launch {
            try {
                val vids = withContext(Dispatchers.IO) {
                    val list = mutableListOf<VideoItem>()
                    val token = authMgr.getAccessToken()
                    if (token != null) {
                        if (subChannels.isEmpty()) subChannels = ytApi.getSubscriptions()
                        if (subChannels.isNotEmpty()) {
                            val randomSub = subChannels.random()
                            try {
                                val ce = ServiceList.YouTube.getChannelExtractor(randomSub.url)
                                ce.fetchPage()
                                val shortsTab = ce.tabs.firstOrNull { it.contentFilters.any { f -> f.contains("shorts", true) } }
                                if (shortsTab != null) {
                                val te = ServiceList.YouTube.getChannelTabExtractor(shortsTab)
                                te.fetchPage()
                                    list.addAll(te.initialPage.items.filterIsInstance<StreamInfoItem>().map { it.toVideoItem() }.filter { it.isShortVideo() && seenShortIds.add(it.id) }.take(5))
                                }
                            } catch (e: Exception) { e.printStackTrace() }
                        }
                    }
                    list.addAll(fetchShortsBatch(targetCount = 10))
                    list.shuffled()
                }
                if (_mode.value == ScreenMode.SHORTS) {
                    _ui.value = if (vids.isEmpty()) UiState.Error("No shorts found") else UiState.Videos(vids)
                }
            } catch (e: Exception) {
                if (_mode.value == ScreenMode.SHORTS) _ui.value = UiState.Error(e.localizedMessage ?: "Failed")
            } finally { isLoadingMore = false }
        }
    }
    
    fun handleSignIn(accountName: String) {
        settingsMgr.accountName = accountName
        if (_mode.value == ScreenMode.SUBSCRIPTIONS) showSubscriptions() else loadMixedFeed(true)
    }
    
    fun logout() {
        settingsMgr.clearAuth()
        subChannels = emptyList()
        loadMixedFeed(true)
    }

    fun loadChannel(url: String, name: String) {
        _mode.value = ScreenMode.CHANNEL; _header.value = name
        viewModelScope.launch {
            _ui.value = UiState.Loading
            try {
                val vids = withContext(Dispatchers.IO) {
                    val ce = ServiceList.YouTube.getChannelExtractor(url); ce.fetchPage()
                    val tab = ce.tabs.firstOrNull { t -> t.contentFilters.any { it.contains("videos", true) } } ?: ce.tabs.firstOrNull() ?: throw Exception("No tabs")
                    val te = ServiceList.YouTube.getChannelTabExtractor(tab)
                    @Suppress("UNCHECKED_CAST")
                    currentExtractor = te as? ListExtractor<InfoItem>
                    te.fetchPage(); nextPageUrl = te.initialPage.nextPage; te.initialPage.items.filterIsInstance<StreamInfoItem>().map { it.toVideoItem() }
                }
                if (_mode.value == ScreenMode.CHANNEL && _header.value == name) {
                    _ui.value = if (vids.isEmpty()) UiState.Error("No videos") else UiState.Videos(vids)
                }
            } catch (e: Exception) {
                if (_mode.value == ScreenMode.CHANNEL && _header.value == name) {
                    _ui.value = UiState.Error(e.localizedMessage ?: "Failed")
                }
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
                    _header.value = "\uD83C\uDFB5 ${pe.name}"; currentExtractor = null; nextPageUrl = null
                    pe.initialPage.items.filterIsInstance<StreamInfoItem>().map { it.toVideoItem() }
                }
                if (_mode.value == ScreenMode.PLAYLIST) {
                    _ui.value = if (vids.isEmpty()) UiState.Error("Empty playlist") else UiState.Videos(vids)
                }
            } catch (e: Exception) {
                if (_mode.value == ScreenMode.PLAYLIST) _ui.value = UiState.Error(e.localizedMessage ?: "Failed")
            }
        }
    }

    fun goBack() { when (_mode.value) { ScreenMode.CHANNEL -> showSubscriptions(); ScreenMode.TAGS -> loadMixedFeed(true); else -> if (lastQuery.isNotBlank()) search(lastQuery) else loadMixedFeed(true) } }
    fun retry() { when (_mode.value) { ScreenMode.FEED -> if (lastQuery.isNotBlank()) search(lastQuery) else loadMixedFeed(true); ScreenMode.SHORTS -> showShorts(); ScreenMode.SUBSCRIPTIONS -> showSubscriptions(); ScreenMode.HISTORY -> showHistory(); ScreenMode.DOWNLOADS -> showDownloads(); ScreenMode.TAGS -> showTags(); else -> loadMixedFeed(true) } }

    private fun InfoItem.toItem(): VideoItem? = when (this) { is StreamInfoItem -> toVideoItem(); is PlaylistInfoItem -> VideoItem(url, "\uD83C\uDFB5 $name", uploaderName.orEmpty(), "${streamCount} videos", thumbnails.firstOrNull()?.url.orEmpty(), url, ItemType.PLAYLIST); else -> null }
    private fun StreamInfoItem.toVideoItem(): VideoItem { val live = streamType == StreamType.LIVE_STREAM || streamType == StreamType.AUDIO_LIVE_STREAM; return VideoItem(url, name, uploaderName.orEmpty(), if (live) "LIVE" else fmtDur(duration), thumbnails.firstOrNull()?.url.orEmpty(), url, ItemType.VIDEO, isLive = live) }

    private fun loadTagPage(tag: String): List<VideoItem> {
        return if (!tagExtractors.containsKey(tag)) {
            val ext = ServiceList.YouTube.getSearchExtractor(tag)
            @Suppress("UNCHECKED_CAST")
            val listExt = ext as ListExtractor<InfoItem>
            tagExtractors[tag] = listExt
            ext.fetchPage()
            tagPages[tag] = ext.initialPage.nextPage
            ext.initialPage.items.mapNotNull { it.toItem() }
        } else {
            val ext = tagExtractors[tag] ?: return emptyList()
            val nextPage = tagPages[tag] ?: return emptyList()
            val page = ext.getPage(nextPage)
            tagPages[tag] = page.nextPage
            page.items.mapNotNull { it.toItem() }
        }
    }

    private fun fetchShortsBatch(targetCount: Int): List<VideoItem> {
        val batch = mutableListOf<VideoItem>()
        var pagesTried = 0
        while (batch.size < targetCount && pagesTried < 8) {
            batch.addAll(fetchShortsPage())
            pagesTried++
        }
        if (batch.isEmpty()) {
            seenShortIds.clear()
            batch.addAll(fetchShortsPage())
        }
        return batch.shuffled()
    }

    private fun fetchShortsPage(): List<VideoItem> {
        val items = if (currentExtractor == null || nextPageUrl == null) {
            val ext = createShortsExtractor()
            ext.initialPage.items
        } else {
            val page = currentExtractor!!.getPage(nextPageUrl)
            nextPageUrl = page.nextPage
            page.items
        }
        return items.mapNotNull { it.toItem() }
            .filter { it.isShortVideo() && seenShortIds.add(it.id) }
    }

    private fun createShortsExtractor(): ListExtractor<InfoItem> {
        val query = shortsQueries[shortsQueryIndex % shortsQueries.size]
        shortsQueryIndex = (shortsQueryIndex + 1) % shortsQueries.size
        val ext = ServiceList.YouTube.getSearchExtractor(query)
        @Suppress("UNCHECKED_CAST")
        val listExt = ext as ListExtractor<InfoItem>
        currentExtractor = listExt
        ext.fetchPage()
        nextPageUrl = ext.initialPage.nextPage
        return listExt
    }

    private fun VideoItem.isShortVideo(): Boolean {
        if (type != ItemType.VIDEO || isLive) return false
        val parts = durationText.split(":").mapNotNull { it.toIntOrNull() }
        val seconds = when (parts.size) {
            2 -> parts[0] * 60 + parts[1]
            3 -> parts[0] * 3600 + parts[1] * 60 + parts[2]
            else -> return false
        }
        return seconds in 1..60
    }

    private fun mergeSubscriptions(local: List<Subscription>, remote: List<Subscription>): List<Subscription> {
        return (remote + local)
            .distinctBy { it.url.trim().trimEnd('/').lowercase() }
            .sortedBy { it.name.lowercase() }
    }
}

private fun fmtDur(s: Long): String { if (s < 0) return "LIVE"; val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60; return if (h > 0) String.format("%d:%02d:%02d", h, m, sec) else String.format("%d:%02d", m, sec) }
private fun ScreenMode.canPageVideos(): Boolean = this == ScreenMode.FEED || this == ScreenMode.CHANNEL || this == ScreenMode.SHORTS
private fun ScreenMode.canShowVideos(): Boolean = this == ScreenMode.FEED || this == ScreenMode.CHANNEL || this == ScreenMode.PLAYLIST || this == ScreenMode.SHORTS

@Composable
fun VideoCard(video: VideoItem, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFF1E1E1E))
            .clickable { onClick() }
            .padding(6.dp)
    ) {
        Box(modifier = Modifier.fillMaxWidth().height(80.dp).clip(RoundedCornerShape(8.dp))) {
            AsyncImage(model = video.thumbnailUrl, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            Box(modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp).background(if (video.isLive) Color(0xFFCC0000) else Color.Black.copy(0.8f), RoundedCornerShape(4.dp))) {
                Text(if (video.isLive) "LIVE" else video.durationText, color = Color.White, style = MaterialTheme.typography.caption3, modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp))
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(video.title, style = MaterialTheme.typography.caption2, maxLines = 2, overflow = TextOverflow.Ellipsis, color = Color.White)
        Text(video.channel, style = MaterialTheme.typography.caption3, color = Color.Gray, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun MainScreen(viewModel: MainViewModel = viewModel()) {
    val ui by viewModel.ui.collectAsState()
    val mode by viewModel.mode.collectAsState()
    val header by viewModel.header.collectAsState()
    val quality by viewModel.quality.collectAsState()
    val activeTags by viewModel.activeTags.collectAsState()
    
    val listState = rememberScalingLazyListState()
    val focus = remember { FocusRequester() }
    val ctx = LocalContext.current
    val histMgr = remember { HistoryManager.getInstance(ctx.applicationContext) }
    val notifPerm = rememberPermissionState(Manifest.permission.POST_NOTIFICATIONS)

    var hasActivePlayer by remember { mutableStateOf(PlaybackService.player?.currentMediaItem != null) }
    LaunchedEffect(Unit) {
        if (!notifPerm.status.isGranted) {
            notifPerm.launchPermissionRequest()
        }
        while(true) {
            hasActivePlayer = PlaybackService.player?.currentMediaItem != null
            kotlinx.coroutines.delay(1000)
        }
    }

    val isAtBottom by remember { derivedStateOf { val layoutInfo = listState.layoutInfo; val totalItems = layoutInfo.totalItemsCount; val lastVisibleItem = layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0; lastVisibleItem >= totalItems - 3 && totalItems > 0 } }
    LaunchedEffect(isAtBottom, mode) { if (isAtBottom && mode.canPageVideos()) viewModel.loadMore() }

    val speechLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result -> if (result.resultCode == Activity.RESULT_OK) { result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()?.takeIf { it.isNotBlank() }?.let { viewModel.search(it) } } }
    
    val gso = remember { GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN).requestEmail().requestScopes(Scope(AuthManager.YOUTUBE_READONLY_SCOPE)).build() }
    val googleSignInClient = remember { GoogleSignIn.getClient(ctx, gso) }
    val authLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        try {
            val task = GoogleSignIn.getSignedInAccountFromIntent(result.data)
            val account = task.getResult(ApiException::class.java)
            val accountName = account?.account?.name ?: account?.email
            if (!accountName.isNullOrBlank()) {
                viewModel.handleSignIn(accountName)
                Toast.makeText(ctx, "Google connected: $accountName", Toast.LENGTH_LONG).show()
            } else {
                Toast.makeText(ctx, "Ошибка входа. Отменено или нет аккаунта.", Toast.LENGTH_LONG).show()
            }
        } catch (e: ApiException) {
            Toast.makeText(ctx, "Ошибка входа (${e.statusCode}): Проверьте SHA-1 в Cloud Console!", Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Toast.makeText(ctx, "Неизвестная ошибка: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    Scaffold(timeText = { TimeText() }, vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) }, positionIndicator = { PositionIndicator(scalingLazyListState = listState) }) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF0F0F0F))
                .rotaryScrollable(behavior = RotaryScrollableDefaults.behavior(listState), focusRequester = focus)
                .focusRequester(focus)
                .focusable()
        ) {
            if (mode == ScreenMode.TAGS) {
                item { Chip(onClick = { viewModel.loadMixedFeed(true) }, label = { Text("Back & Refresh") }, icon = { Icon(Icons.Rounded.Refresh, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                item { Text("Select Feed Topics", style = MaterialTheme.typography.caption1, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) }
                items(MainViewModel.AVAILABLE_TAGS.size) { i ->
                    val tag = MainViewModel.AVAILABLE_TAGS[i]
                    val isSelected = activeTags.contains(tag)
                    Chip(onClick = { viewModel.toggleTag(tag) }, label = { Text(tag) }, secondaryLabel = { Text(if (isSelected) "Enabled" else "Disabled", color = if(isSelected) Color.Green else Color.Gray) }, colors = if (isSelected) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth())
                }
            } else {
                item { Chip(onClick = { try { speechLauncher.launch(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply { putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM); putExtra(RecognizerIntent.EXTRA_PROMPT, "Search") }) } catch (e: Exception) {} }, label = { Text("Search YouTube") }, icon = { Icon(Icons.Rounded.Search, null, tint = Color.White) }, colors = ChipDefaults.chipColors(backgroundColor = Color(0xFFCC0000)), modifier = Modifier.fillMaxWidth()) }

                if (hasActivePlayer) {
                    item { Chip(onClick = { ctx.startActivity(Intent(ctx, PlayerActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP; putExtra("from_notification", true) }) }, label = { Text("Now Playing") }, secondaryLabel = { Text("Tap to resume video") }, icon = { Icon(Icons.Rounded.PlayArrow, null, tint = Color.Green) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                }

                if (mode == ScreenMode.FEED) {
                    item { Chip(onClick = { viewModel.showTags() }, label = { Text("Feed Topics") }, icon = { Icon(Icons.Rounded.List, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    item { Chip(onClick = { viewModel.showSubscriptions() }, label = { Text("Subscriptions") }, icon = { Icon(Icons.Rounded.Favorite, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    item { Chip(onClick = { viewModel.showHistory() }, label = { Text("History") }, icon = { Icon(Icons.Rounded.History, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    item { Chip(onClick = { viewModel.showDownloads() }, label = { Text("Downloads") }, icon = { Icon(Icons.Rounded.Download, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    item { Chip(onClick = { viewModel.showShorts() }, label = { Text("Shorts") }, icon = { Icon(Icons.Rounded.PlayArrow, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    item { 
                        val account = viewModel.settingsMgr.accountName
                        if (account.isBlank()) {
                            CompactChip(onClick = { authLauncher.launch(googleSignInClient.signInIntent) }, label = { Text("Google Login") }, icon = { Icon(Icons.Rounded.Settings, null, modifier = Modifier.size(16.dp)) }, colors = ChipDefaults.primaryChipColors()) 
                        } else {
                            Chip(onClick = { googleSignInClient.signOut(); viewModel.logout(); Toast.makeText(ctx, "Logged out", Toast.LENGTH_SHORT).show() }, label = { Text("Logout", maxLines = 1, overflow = TextOverflow.Ellipsis) }, secondaryLabel = { Text(account, maxLines = 1, overflow = TextOverflow.Ellipsis) }, icon = { Icon(Icons.Rounded.Settings, null, modifier = Modifier.size(24.dp)) }, colors = ChipDefaults.chipColors(backgroundColor = Color(0xFFCC0000)), modifier = Modifier.fillMaxWidth()) 
                        }
                    }
                    item { CompactChip(onClick = { viewModel.cycleQuality() }, label = { Text("Quality: ${quality.label}") }, icon = { Icon(Icons.Rounded.Settings, null, modifier = Modifier.size(16.dp)) }, colors = ChipDefaults.secondaryChipColors()) }
                } else {
                    item { Chip(onClick = { viewModel.goBack() }, label = { Text("Back") }, icon = { Icon(Icons.Rounded.ArrowBack, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                }

                if (mode == ScreenMode.SUBSCRIPTIONS) {
                    if (viewModel.settingsMgr.accountName.isNotBlank()) {
                        item { Chip(onClick = { authLauncher.launch(googleSignInClient.signInIntent) }, label = { Text("Sync Google") }, icon = { Icon(Icons.Rounded.Refresh, null) }, colors = ChipDefaults.primaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    }
                }

                item { Text(header, style = MaterialTheme.typography.caption1, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }

                when (val s = ui) {
                    is UiState.Loading -> item { Box(Modifier.fillMaxWidth().height(80.dp), contentAlignment = Alignment.Center) { Text("Loading\u2026", style = MaterialTheme.typography.body1) } }
                    is UiState.Error -> item { Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) { Text(s.message, style = MaterialTheme.typography.body2, textAlign = TextAlign.Center, maxLines = 6, overflow = TextOverflow.Ellipsis); Chip(onClick = { viewModel.retry() }, label = { Text("Retry") }, colors = ChipDefaults.chipColors(backgroundColor = Color(0xFFCC0000))) } }
                    is UiState.Channels -> items(s.subs.size) { i -> val sub = s.subs[i]; Chip(onClick = { viewModel.loadChannel(sub.url, sub.name) }, label = { Text(sub.name, maxLines = 2, overflow = TextOverflow.Ellipsis) }, icon = { if (sub.avatarUrl.isNotEmpty()) AsyncImage(model = sub.avatarUrl, contentDescription = null, modifier = Modifier.size(24.dp).clip(androidx.compose.foundation.shape.CircleShape), contentScale = ContentScale.Crop) else Icon(Icons.Rounded.PlayArrow, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.fillMaxWidth()) }
                    is UiState.History -> items(s.entries.size) { i -> val e = s.entries[i]; val vId = e.url.substringAfter("v=", "").substringBefore("&").ifEmpty { e.url.substringAfterLast("/") }; val thumb = if (vId.isNotEmpty() && !e.url.startsWith("file://")) "https://i.ytimg.com/vi/$vId/hqdefault.jpg" else ""; VideoCard(VideoItem(vId, e.title, "History", if (e.positionMs > 0) "Resume: ${fmtDur(e.positionMs/1000)}" else "", thumb, e.url, ItemType.VIDEO, false)) { ctx.startActivity(PlayerActivity.newIntent(ctx, e.url, e.title)) } }
                    is UiState.Downloads -> items(s.entries.size) { i -> val e = s.entries[i]; Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) { Chip(onClick = { ctx.startActivity(PlayerActivity.newIntent(ctx, "file://${e.filePath}", e.title)) }, label = { Text(e.title, maxLines = 2, overflow = TextOverflow.Ellipsis) }, icon = { Icon(Icons.Rounded.PlayArrow, null) }, colors = ChipDefaults.secondaryChipColors(), modifier = Modifier.weight(1f)); Button(onClick = { viewModel.deleteDownload(e.fileName) }, modifier = Modifier.size(52.dp), colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFCC0000))) { Icon(Icons.Rounded.Close, null) } } }
                    is UiState.Videos -> if (mode.canShowVideos()) items(s.videos.size) { i ->
                        val v = s.videos[i]
                        VideoCard(v) {
                            if (v.type == ItemType.PLAYLIST) {
                                viewModel.loadPlaylist(v.videoUrl)
                            } else {
                                histMgr.add(v.videoUrl, v.title, 0L)
                                val allVids = s.videos.filter { it.type == ItemType.VIDEO }
                                val playbackContext = when (mode) {
                                    ScreenMode.SHORTS -> PlaybackContext.SHORTS
                                    ScreenMode.CHANNEL -> PlaybackContext.CHANNEL
                                    ScreenMode.PLAYLIST -> PlaybackContext.PLAYLIST
                                    ScreenMode.FEED -> PlaybackContext.FEED
                                    else -> PlaybackContext.SINGLE
                                }
                                val idx = allVids.indexOfFirst { it.videoUrl == v.videoUrl }.coerceAtLeast(0)
                                if (playbackContext != PlaybackContext.SINGLE && allVids.size > 1) {
                                    ctx.startActivity(PlayerActivity.newQueueIntent(ctx, ArrayList(allVids.map { it.videoUrl }), ArrayList(allVids.map { it.title }), idx, playbackContext))
                                } else {
                                    ctx.startActivity(PlayerActivity.newIntent(ctx, v.videoUrl, v.title, playbackContext))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    LaunchedEffect(mode, ui) {
        kotlinx.coroutines.delay(100)
        runCatching { focus.requestFocus() }
    }
}
