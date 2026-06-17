# generate_phase4.ps1
# TicTube Wear OS - Phase 4: Voice Search + Local Subscriptions
# Run from project root: S:\_Vibe_Coding\TicTube\WearApp
#
# Generates/Overwrites 3 files:
#   1. SubscriptionManager.kt  - NEW  - SharedPreferences subscription store
#   2. MainScreen.kt           - OVERWRITE - Search chip, Subscriptions chip,
#                                 channel videos, AndroidViewModel
#   3. PlayerScreen.kt         - OVERWRITE - Subscribe/Unsubscribe toggle
#
# MainActivity.kt is NOT touched (no changes required).
#
# Uses single-quoted here-strings (@'...'@) to avoid PowerShell
# interpreting Kotlin's $ string templates.

$ErrorActionPreference = "Stop"
$basePath = Join-Path $PSScriptRoot "app\src\main\java\com\tictube"

if (-not (Test-Path $basePath)) {
    New-Item -ItemType Directory -Force -Path $basePath | Out-Null
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host " TicTube Phase 4 - Search + Subscriptions       " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. SubscriptionManager.kt  (NEW)
# ============================================================
$subscriptionManagerContent = @'
package com.tictube

import android.content.Context
import android.content.SharedPreferences

/**
 * Lightweight channel subscription store backed by [SharedPreferences].
 *
 * Each subscription is persisted as a single string in the format
 * `"channelUrl||channelName"` inside a `StringSet`.
 *
 * Thread-safety: [SharedPreferences] reads are thread-safe; writes use
 * [SharedPreferences.Editor.apply] (async, non-blocking).
 */
class SubscriptionManager private constructor(context: Context) {

    companion object {
        private const val PREFS_NAME = "tictube_subscriptions"
        private const val KEY_CHANNELS = "subscribed_channels"
        private const val SEPARATOR = "||"

        @Volatile
        private var instance: SubscriptionManager? = null

        fun getInstance(context: Context): SubscriptionManager {
            return instance ?: synchronized(this) {
                instance ?: SubscriptionManager(context.applicationContext)
                    .also { instance = it }
            }
        }
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Subscribe to a channel. Duplicates (by URL) are silently ignored. */
    fun subscribe(url: String, name: String) {
        if (url.isBlank()) return
        val current = rawSet().toMutableSet()
        // Remove any existing entry for this URL first (name might have changed)
        current.removeAll { it.startsWith("$url$SEPARATOR") }
        current.add("$url$SEPARATOR$name")
        prefs.edit().putStringSet(KEY_CHANNELS, current).apply()
    }

    /** Unsubscribe from a channel by its URL. */
    fun unsubscribe(url: String) {
        val current = rawSet().toMutableSet()
        current.removeAll { it.startsWith("$url$SEPARATOR") }
        prefs.edit().putStringSet(KEY_CHANNELS, current).apply()
    }

    /** Check whether a channel URL is currently subscribed. */
    fun isSubscribed(url: String): Boolean {
        return rawSet().any { it.startsWith("$url$SEPARATOR") }
    }

    /** Return all subscriptions sorted alphabetically by name. */
    fun getAll(): List<Subscription> {
        return rawSet().mapNotNull { entry ->
            val parts = entry.split(SEPARATOR, limit = 2)
            if (parts.size == 2 && parts[0].isNotBlank())
                Subscription(url = parts[0], name = parts[1])
            else null
        }.sortedBy { it.name.lowercase() }
    }

    /** Number of subscribed channels. */
    fun count(): Int = rawSet().size

    private fun rawSet(): Set<String> =
        prefs.getStringSet(KEY_CHANNELS, emptySet()) ?: emptySet()
}

/** A subscribed channel. */
data class Subscription(val url: String, val name: String)
'@

$subscriptionManagerPath = Join-Path $basePath "SubscriptionManager.kt"
[System.IO.File]::WriteAllText($subscriptionManagerPath, $subscriptionManagerContent, $utf8NoBom)
Write-Host "  [OK] SubscriptionManager.kt (NEW)" -ForegroundColor Green

# ============================================================
# 2. MainScreen.kt  (OVERWRITE)
# ============================================================
$mainScreenContent = @'
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
import androidx.compose.runtime.remember
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
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.StreamInfoItem

// ─── Data Model ───────────────────────────────────────────────

data class VideoItem(
    val id: String,
    val title: String,
    val channel: String,
    val durationText: String,
    val thumbnailUrl: String = "",
    val videoUrl: String = ""
)

// ─── UI State ─────────────────────────────────────────────────

sealed interface UiState {
    object Loading : UiState
    data class Videos(val videos: List<VideoItem>) : UiState
    data class Channels(val subscriptions: List<Subscription>) : UiState
    data class Error(val message: String) : UiState
}

enum class ScreenMode { FEED, SUBSCRIPTIONS, CHANNEL }

// ─── ViewModel ────────────────────────────────────────────────

class MainViewModel(application: Application) : AndroidViewModel(application) {

    companion object {
        private const val TAG = "MainViewModel"
        private const val DEFAULT_QUERY = "Tech News"
        private const val MAX_RESULTS = 20
    }

    private val subManager = SubscriptionManager.getInstance(application)

    private val _screenMode = MutableStateFlow(ScreenMode.FEED)
    val screenMode: StateFlow<ScreenMode> = _screenMode.asStateFlow()

    private val _uiState = MutableStateFlow<UiState>(UiState.Loading)
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private val _headerTitle = MutableStateFlow(DEFAULT_QUERY)
    val headerTitle: StateFlow<String> = _headerTitle.asStateFlow()

    private var lastSearchQuery: String = DEFAULT_QUERY

    init {
        search(DEFAULT_QUERY)
    }

    // ── YouTube search ────────────────────────────────────────

    fun search(query: String) {
        lastSearchQuery = query
        _screenMode.value = ScreenMode.FEED
        _headerTitle.value = "\uD83D\uDD0D $query"
        viewModelScope.launch {
            _uiState.value = UiState.Loading
            try {
                val videos = withContext(Dispatchers.IO) {
                    val extractor = ServiceList.YouTube.getSearchExtractor(query)
                    extractor.fetchPage()
                    extractor.initialPage.items
                        .filterIsInstance<StreamInfoItem>()
                        .take(MAX_RESULTS)
                        .map { it.toVideoItem() }
                }
                _uiState.value = if (videos.isEmpty()) UiState.Error("No results for \"$query\"")
                else UiState.Videos(videos)
            } catch (e: Exception) {
                Log.e(TAG, "Search failed: $query", e)
                _uiState.value = UiState.Error(e.localizedMessage ?: "Search failed")
            }
        }
    }

    // ── Subscriptions list ────────────────────────────────────

    fun showSubscriptions() {
        _screenMode.value = ScreenMode.SUBSCRIPTIONS
        _headerTitle.value = "\u2764\uFE0F My Channels"
        val subs = subManager.getAll()
        _uiState.value = if (subs.isEmpty())
            UiState.Error("No subscriptions yet.\nWatch a video and tap \u2661 Subscribe!")
        else
            UiState.Channels(subs)
    }

    // ── Channel videos ────────────────────────────────────────

    fun loadChannelVideos(channelUrl: String, channelName: String) {
        _screenMode.value = ScreenMode.CHANNEL
        _headerTitle.value = channelName
        viewModelScope.launch {
            _uiState.value = UiState.Loading
            try {
                val videos = withContext(Dispatchers.IO) {
                    val channelExtractor =
                        ServiceList.YouTube.getChannelExtractor(channelUrl)
                    channelExtractor.fetchPage()

                    // Channels expose content via tabs (Videos, Shorts, etc.)
                    val tabs = channelExtractor.tabs
                    val videosTab = tabs.firstOrNull { tab ->
                        tab.contentFilters.any { it.contains("videos", ignoreCase = true) }
                    } ?: tabs.firstOrNull()
                        ?: throw IllegalStateException("Channel has no content tabs")

                    val tabExtractor =
                        ServiceList.YouTube.getChannelTabExtractor(videosTab)
                    tabExtractor.fetchPage()
                    tabExtractor.initialPage.items
                        .filterIsInstance<StreamInfoItem>()
                        .take(MAX_RESULTS)
                        .map { it.toVideoItem() }
                }
                _uiState.value = if (videos.isEmpty()) UiState.Error("No videos found")
                else UiState.Videos(videos)
            } catch (e: Exception) {
                Log.e(TAG, "Channel load failed: $channelUrl", e)
                _uiState.value = UiState.Error(e.localizedMessage ?: "Failed to load channel")
            }
        }
    }

    // ── Navigation helpers ────────────────────────────────────

    /** Context-aware back: Channel → Subscriptions → Feed. */
    fun goBack() {
        when (_screenMode.value) {
            ScreenMode.CHANNEL -> showSubscriptions()
            ScreenMode.SUBSCRIPTIONS -> search(lastSearchQuery)
            ScreenMode.FEED -> { /* Already at root */ }
        }
    }

    fun retry() {
        when (_screenMode.value) {
            ScreenMode.FEED -> search(lastSearchQuery)
            ScreenMode.SUBSCRIPTIONS -> showSubscriptions()
            ScreenMode.CHANNEL -> { /* User should go back */ }
        }
    }

    // ── Mapping helper ────────────────────────────────────────

    private fun StreamInfoItem.toVideoItem() = VideoItem(
        id = url,
        title = name,
        channel = uploaderName.orEmpty(),
        durationText = formatDuration(duration),
        thumbnailUrl = thumbnails.firstOrNull()?.url.orEmpty(),
        videoUrl = url
    )
}

// ─── Helpers ──────────────────────────────────────────────────

private fun formatDuration(seconds: Long): String {
    if (seconds < 0) return "LIVE"
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return if (h > 0) String.format("%d:%02d:%02d", h, m, s)
    else String.format("%d:%02d", m, s)
}

// ─── Composable ───────────────────────────────────────────────

@Composable
fun MainScreen(
    viewModel: MainViewModel = viewModel(),
    onVideoClick: (VideoItem) -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val screenMode by viewModel.screenMode.collectAsState()
    val headerTitle by viewModel.headerTitle.collectAsState()
    val listState = rememberScalingLazyListState()
    val focusRequester = remember { FocusRequester() }
    val context = LocalContext.current

    // ── Voice / keyboard search launcher ──────────────────────
    val speechLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val spoken = result.data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
            if (!spoken.isNullOrBlank()) {
                viewModel.search(spoken)
            }
        }
    }

    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) }
    ) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .rotaryScrollable(
                    behavior = RotaryScrollableDefaults.behavior(
                        scrollableState = listState
                    ),
                    focusRequester = focusRequester
                )
                .focusRequester(focusRequester)
                .focusable()
        ) {
            // ── 1. Search chip (always visible) ───────────────
            item {
                Chip(
                    onClick = {
                        try {
                            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                putExtra(
                                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                                )
                                putExtra(RecognizerIntent.EXTRA_PROMPT, "Search YouTube")
                            }
                            speechLauncher.launch(intent)
                        } catch (e: Exception) {
                            Log.e("MainScreen", "Speech input unavailable", e)
                        }
                    },
                    label = { Text("\uD83D\uDD0D Search YouTube") },
                    colors = ChipDefaults.primaryChipColors(),
                    modifier = Modifier.fillMaxWidth()
                )
            }

            // ── 2. Context chip (Subscriptions / Back) ────────
            item {
                when (screenMode) {
                    ScreenMode.FEED -> {
                        Chip(
                            onClick = { viewModel.showSubscriptions() },
                            label = { Text("\u2764\uFE0F Subscriptions") },
                            colors = ChipDefaults.secondaryChipColors(),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    ScreenMode.SUBSCRIPTIONS,
                    ScreenMode.CHANNEL -> {
                        Chip(
                            onClick = { viewModel.goBack() },
                            label = { Text("\u2190 Back") },
                            colors = ChipDefaults.secondaryChipColors(),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }

            // ── 3. Header label ───────────────────────────────
            item {
                Text(
                    text = headerTitle,
                    style = MaterialTheme.typography.caption1,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            // ── 4. Content ────────────────────────────────────
            when (val state = uiState) {

                is UiState.Loading -> {
                    item {
                        Box(
                            Modifier.fillMaxWidth().height(80.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                "Loading\u2026",
                                style = MaterialTheme.typography.body1
                            )
                        }
                    }
                }

                is UiState.Error -> {
                    item {
                        Column(
                            Modifier.fillMaxWidth(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text(
                                state.message,
                                style = MaterialTheme.typography.body2,
                                textAlign = TextAlign.Center,
                                maxLines = 4,
                                overflow = TextOverflow.Ellipsis
                            )
                            Spacer(Modifier.height(4.dp))
                            Chip(
                                onClick = { viewModel.retry() },
                                label = { Text("Retry") },
                                colors = ChipDefaults.primaryChipColors()
                            )
                        }
                    }
                }

                is UiState.Channels -> {
                    items(state.subscriptions.size) { index ->
                        val sub = state.subscriptions[index]
                        Chip(
                            onClick = {
                                viewModel.loadChannelVideos(sub.url, sub.name)
                            },
                            label = {
                                Text(
                                    text = sub.name,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                            },
                            secondaryLabel = {
                                Text("Tap to view videos")
                            },
                            colors = ChipDefaults.gradientBackgroundChipColors(),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }

                is UiState.Videos -> {
                    items(state.videos.size) { index ->
                        val video = state.videos[index]
                        Chip(
                            onClick = { onVideoClick(video) },
                            label = {
                                Text(
                                    text = video.title,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                            },
                            secondaryLabel = {
                                Text(
                                    text = "${video.channel} \u2022 ${video.durationText}",
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            },
                            icon = {
                                AsyncImage(
                                    model = video.thumbnailUrl,
                                    contentDescription = null,
                                    modifier = Modifier
                                        .size(32.dp)
                                        .clip(RoundedCornerShape(4.dp)),
                                    contentScale = ContentScale.Crop
                                )
                            },
                            colors = ChipDefaults.secondaryChipColors(),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }
        }
    }

    // Scroll to top when screen mode changes
    LaunchedEffect(screenMode) {
        listState.scrollToItem(0)
        focusRequester.requestFocus()
    }
}
'@

$mainScreenPath = Join-Path $basePath "MainScreen.kt"
[System.IO.File]::WriteAllText($mainScreenPath, $mainScreenContent, $utf8NoBom)
Write-Host "  [OK] MainScreen.kt (OVERWRITE)" -ForegroundColor Green

# ============================================================
# 3. PlayerScreen.kt  (OVERWRITE - includes PlayerActivity)
# ============================================================
$playerScreenContent = @'
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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.ServiceList

// ─── Activity ─────────────────────────────────────────────────

class PlayerActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startService(Intent(this, PlaybackService::class.java))

        val videoUrl   = intent.getStringExtra(EXTRA_VIDEO_URL).orEmpty()
        val videoTitle = intent.getStringExtra(EXTRA_VIDEO_TITLE).orEmpty()

        setContent {
            MaterialTheme {
                PlayerScreen(videoUrl = videoUrl, videoTitle = videoTitle)
            }
        }
    }

    companion object {
        const val EXTRA_VIDEO_URL   = "extra_video_url"
        const val EXTRA_VIDEO_TITLE = "extra_video_title"

        fun newIntent(context: Context, videoUrl: String, videoTitle: String): Intent {
            return Intent(context, PlayerActivity::class.java).apply {
                putExtra(EXTRA_VIDEO_URL, videoUrl)
                putExtra(EXTRA_VIDEO_TITLE, videoTitle)
            }
        }
    }
}

// ─── Stream extraction result ─────────────────────────────────

private data class StreamExtractionResult(
    val streamUrl: String,
    val uploaderUrl: String,
    val uploaderName: String
)

/**
 * Resolves a YouTube page URL into a direct playable stream URL
 * AND extracts uploader metadata for the subscription feature.
 *
 * Strategy:
 *  1. Muxed (video+audio) streams — pick closest to 360p.
 *  2. Fallback to highest-bitrate audio-only stream.
 */
private suspend fun extractStream(youtubeUrl: String): StreamExtractionResult {
    return withContext(Dispatchers.IO) {
        val extractor = ServiceList.YouTube.getStreamExtractor(youtubeUrl)
        extractor.fetchPage()

        val uploaderUrl  = extractor.uploaderUrl.orEmpty()
        val uploaderName = extractor.uploaderName.orEmpty()

        // 1. Muxed streams
        val muxed = try {
            extractor.videoStreams?.filter { it.isUrl } ?: emptyList()
        } catch (e: Exception) {
            Log.w("StreamExtract", "No muxed streams", e)
            emptyList()
        }

        if (muxed.isNotEmpty()) {
            val best = muxed.minByOrNull { stream ->
                val res = stream.resolution
                    ?.replace(Regex("p.*"), "")
                    ?.toIntOrNull() ?: 999
                kotlin.math.abs(res - 360)
            }
            val url = best?.content
            if (!url.isNullOrBlank()) {
                return@withContext StreamExtractionResult(url, uploaderUrl, uploaderName)
            }
        }

        // 2. Audio-only fallback
        val audio = try {
            extractor.audioStreams?.filter { it.isUrl } ?: emptyList()
        } catch (e: Exception) {
            Log.w("StreamExtract", "No audio streams", e)
            emptyList()
        }
        val bestAudio = audio.maxByOrNull { it.averageBitrate }
        val audioUrl = bestAudio?.content
        if (!audioUrl.isNullOrBlank()) {
            return@withContext StreamExtractionResult(audioUrl, uploaderUrl, uploaderName)
        }

        throw IllegalStateException("No playable streams found")
    }
}

// ─── Composable ───────────────────────────────────────────────

@Composable
fun PlayerScreen(videoUrl: String, videoTitle: String) {
    val context        = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val audioManager   = remember {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    val subManager = remember {
        SubscriptionManager.getInstance(context.applicationContext)
    }
    val focusRequester = remember { FocusRequester() }

    var showControls  by remember { mutableStateOf(false) }
    var isPlaying     by remember { mutableStateOf(false) }
    var isLoading     by remember { mutableStateOf(true) }
    var errorMessage  by remember { mutableStateOf<String?>(null) }
    var player        by remember { mutableStateOf(PlaybackService.player) }

    // Uploader metadata for subscription
    var uploaderUrl   by remember { mutableStateOf("") }
    var uploaderName  by remember { mutableStateOf("") }
    var isSubscribed  by remember { mutableStateOf(false) }

    // ── Wait for PlaybackService ──────────────────────────────
    LaunchedEffect(Unit) {
        while (player == null) {
            delay(100L)
            player = PlaybackService.player
        }
    }

    // ── Extract stream URL & start playback ───────────────────
    LaunchedEffect(player, videoUrl) {
        val p = player ?: return@LaunchedEffect
        if (videoUrl.isEmpty()) return@LaunchedEffect

        isLoading = true
        errorMessage = null

        try {
            val result = extractStream(videoUrl)
            // Update uploader info for subscribe button
            uploaderUrl  = result.uploaderUrl
            uploaderName = result.uploaderName
            isSubscribed = subManager.isSubscribed(result.uploaderUrl)

            // Set media and play (back on Main thread)
            p.setMediaItem(MediaItem.fromUri(result.streamUrl))
            p.prepare()
            p.playWhenReady = true
            isLoading = false
            showControls = true // Show controls briefly on load
        } catch (e: Exception) {
            Log.e("PlayerScreen", "Stream extraction failed", e)
            isLoading = false
            errorMessage = e.localizedMessage ?: "Could not load video"
        }
    }

    // ── Auto-hide controls ────────────────────────────────────
    LaunchedEffect(showControls) {
        if (showControls) {
            delay(5000L)
            showControls = false
        }
    }

    // ── Sync isPlaying from Player ────────────────────────────
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }
        }
        player?.addListener(listener)
        onDispose { player?.removeListener(listener) }
    }

    // ── Lifecycle awareness ───────────────────────────────────
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START) {
                player?.let { isPlaying = it.isPlaying }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // ── UI ────────────────────────────────────────────────────
    Box(
        modifier = Modifier
            .fillMaxSize()
            .clip(CircleShape)
            .background(Color.Black)
            .onRotaryScrollEvent { event ->
                val direction = if (event.verticalScrollPixels > 0f)
                    AudioManager.ADJUST_RAISE
                else
                    AudioManager.ADJUST_LOWER
                audioManager.adjustStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    direction,
                    AudioManager.FLAG_SHOW_UI
                )
                true
            }
            .focusRequester(focusRequester)
            .focusable()
            .clickable { showControls = !showControls },
        contentAlignment = Alignment.Center
    ) {
        // ── Video surface ─────────────────────────────────────
        if (!isLoading && errorMessage == null) {
            player?.let { exoPlayer ->
                AndroidView(
                    factory = { ctx ->
                        PlayerView(ctx).apply {
                            this.player = exoPlayer
                            useController = false
                            setKeepScreenOn(true)
                        }
                    },
                    update = { view -> view.player = player },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }

        // ── Loading state ─────────────────────────────────────
        if (isLoading) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    "Extracting stream\u2026",
                    color = Color.White,
                    style = MaterialTheme.typography.body1
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    videoTitle,
                    color = Color.Gray,
                    style = MaterialTheme.typography.caption3,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center
                )
            }
        }

        // ── Error state ───────────────────────────────────────
        if (errorMessage != null) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    "\u26A0 Playback Error",
                    color = Color(0xFFFF6B6B),
                    style = MaterialTheme.typography.title3
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    errorMessage ?: "",
                    color = Color.White,
                    style = MaterialTheme.typography.caption3,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center
                )
                Spacer(Modifier.height(8.dp))
                Chip(
                    onClick = { (context as? ComponentActivity)?.finish() },
                    label = { Text("Back") },
                    colors = ChipDefaults.secondaryChipColors()
                )
            }
        }

        // ── Controls overlay (Play/Pause + Subscribe) ─────────
        if (showControls && !isLoading && errorMessage == null && player != null) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // Play / Pause
                Button(
                    onClick = {
                        player?.let { p ->
                            if (p.isPlaying) p.pause() else p.play()
                        }
                    },
                    modifier = Modifier.size(ButtonDefaults.LargeButtonSize),
                    colors = ButtonDefaults.buttonColors(
                        backgroundColor = Color.Black.copy(alpha = 0.55f)
                    )
                ) {
                    Text(
                        text = if (isPlaying) "\u23F8" else "\u25B6",
                        style = MaterialTheme.typography.title1,
                        color = Color.White
                    )
                }

                // Subscribe / Unsubscribe toggle
                if (uploaderUrl.isNotEmpty()) {
                    CompactChip(
                        onClick = {
                            if (isSubscribed) {
                                subManager.unsubscribe(uploaderUrl)
                            } else {
                                subManager.subscribe(uploaderUrl, uploaderName)
                            }
                            isSubscribed = !isSubscribed
                            // Keep controls visible so user sees the change
                            showControls = true
                        },
                        label = {
                            Text(
                                text = if (isSubscribed)
                                    "\u2764 ${uploaderName.take(12)}"
                                else
                                    "\u2661 Subscribe",
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        },
                        colors = if (isSubscribed)
                            ChipDefaults.primaryChipColors()
                        else
                            ChipDefaults.secondaryChipColors()
                    )
                }
            }
        }
    }

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }
}
'@

$playerScreenPath = Join-Path $basePath "PlayerScreen.kt"
[System.IO.File]::WriteAllText($playerScreenPath, $playerScreenContent, $utf8NoBom)
Write-Host "  [OK] PlayerScreen.kt (OVERWRITE)" -ForegroundColor Green

# ============================================================
# Done
# ============================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " Phase 4 complete - 3 files generated            " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Files:" -ForegroundColor White
Write-Host "  $subscriptionManagerPath  (NEW)" -ForegroundColor Gray
Write-Host "  $mainScreenPath           (OVERWRITE)" -ForegroundColor Gray
Write-Host "  $playerScreenPath         (OVERWRITE)" -ForegroundColor Gray
Write-Host ""
Write-Host "MainActivity.kt was NOT modified (no changes needed)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "What changed:" -ForegroundColor White
Write-Host "  - SubscriptionManager: SharedPreferences store for channels" -ForegroundColor Gray
Write-Host "  - MainScreen:" -ForegroundColor Gray
Write-Host "      Search chip -> ACTION_RECOGNIZE_SPEECH (voice + keyboard)" -ForegroundColor Gray
Write-Host "      Subscriptions chip -> saved channels list" -ForegroundColor Gray
Write-Host "      Channel tap -> fetch videos via ChannelTabExtractor" -ForegroundColor Gray
Write-Host "      Back chip -> context-aware (Channel->Subs->Feed)" -ForegroundColor Gray
Write-Host "      AndroidViewModel for SharedPreferences access" -ForegroundColor Gray
Write-Host "  - PlayerScreen:" -ForegroundColor Gray
Write-Host "      Subscribe/Unsubscribe CompactChip in controls overlay" -ForegroundColor Gray
Write-Host "      Uploader metadata extracted alongside stream URL" -ForegroundColor Gray
Write-Host "      Auto-hide extended to 5s for subscribe interaction" -ForegroundColor Gray
Write-Host ""
Write-Host "Next: run '.\build_apk.ps1' to compile." -ForegroundColor Yellow
