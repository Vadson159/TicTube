# generate_phase3.ps1
# TicTube Wear OS - Phase 3: NewPipeExtractor Integration
# Run from project root: S:\_Vibe_Coding\TicTube\WearApp
#
# Generates/Overwrites 5 files:
#   1. DownloaderImpl.kt    - HttpURLConnection bridge for NewPipeExtractor
#   2. TicTubeApp.kt        - Updated init with real Downloader
#   3. MainScreen.kt        - Real YouTube search + Coil thumbnails
#   4. PlayerScreen.kt      - Stream extraction + Media3 playback
#   5. PlaybackService.kt   - Unchanged but rewritten for completeness
#
# Uses single-quoted here-strings (@'...'@) to avoid PowerShell
# interpolating Kotlin's $ string templates.

$ErrorActionPreference = "Stop"
$basePath = Join-Path $PSScriptRoot "app\src\main\java\com\tictube"

if (-not (Test-Path $basePath)) {
    New-Item -ItemType Directory -Force -Path $basePath | Out-Null
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host " TicTube Phase 3 - NewPipeExtractor Integration " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. DownloaderImpl.kt
# ============================================================
$downloaderContent = @'
package com.tictube

import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/**
 * Concrete [Downloader] implementation for NewPipeExtractor using
 * [HttpURLConnection]. Zero external dependencies — no OkHttp needed.
 *
 * Handles:
 * - GET / POST / HEAD requests
 * - Custom request headers forwarding
 * - POST body writing
 * - Redirect following (automatic via [HttpURLConnection])
 * - Error-stream reading for non-2xx responses
 *
 * Thread-safety: this class is stateless and safe for concurrent use.
 */
class DownloaderImpl private constructor() : Downloader() {

    companion object {
        private val INSTANCE = DownloaderImpl()
        fun getInstance(): DownloaderImpl = INSTANCE

        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; rv:102.0) Gecko/20100101 Firefox/102.0"
        private const val CONNECT_TIMEOUT_MS = 30_000
        private const val READ_TIMEOUT_MS = 30_000
    }

    @Throws(IOException::class)
    override fun execute(request: Request): Response {
        val url = URL(request.url())
        val connection = url.openConnection() as HttpURLConnection

        connection.apply {
            requestMethod = request.httpMethod()
            connectTimeout = CONNECT_TIMEOUT_MS
            readTimeout = READ_TIMEOUT_MS
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", USER_AGENT)
        }

        // Forward all request headers
        for ((headerName, headerValues) in request.headers()) {
            for (headerValue in headerValues) {
                connection.addRequestProperty(headerName, headerValue)
            }
        }

        // Write request body if present (POST, PUT, etc.)
        val body = request.dataToSend()
        if (body != null) {
            connection.doOutput = true
            connection.outputStream.use { it.write(body) }
        }

        val responseCode = connection.responseCode
        val responseMessage = connection.responseMessage.orEmpty()

        // Read response body — prefer inputStream, fall back to errorStream
        val responseBody: String = try {
            readStream(connection.inputStream)
        } catch (_: IOException) {
            try {
                readStream(connection.errorStream)
            } catch (_: Exception) {
                ""
            }
        }

        // Collect response headers (skip null keys from HTTP/1.0 status lines)
        val responseHeaders = mutableMapOf<String, List<String>>()
        for ((key, values) in connection.headerFields) {
            if (key != null) {
                responseHeaders[key] = values
            }
        }

        // Use connection.url for the latestUrl to capture any redirects
        return Response(
            responseCode,
            responseMessage,
            responseHeaders,
            responseBody,
            connection.url.toString()
        )
    }

    private fun readStream(stream: InputStream?): String {
        return stream?.bufferedReader()?.use { it.readText() } ?: ""
    }
}
'@

$downloaderPath = Join-Path $basePath "DownloaderImpl.kt"
[System.IO.File]::WriteAllText($downloaderPath, $downloaderContent, $utf8NoBom)
Write-Host "  [OK] DownloaderImpl.kt" -ForegroundColor Green

# ============================================================
# 2. TicTubeApp.kt
# ============================================================
$appContent = @'
package com.tictube

import android.app.Application
import android.util.Log
import org.schabi.newpipe.extractor.NewPipe

/**
 * Application entry point.
 * Initializes [NewPipe] with our [DownloaderImpl] so that all
 * Extractor calls (search, stream extraction) have a working
 * HTTP backend from the very first Activity launch.
 */
class TicTubeApp : Application() {

    companion object {
        private const val TAG = "TicTubeApp"
    }

    override fun onCreate() {
        super.onCreate()
        try {
            NewPipe.init(DownloaderImpl.getInstance())
            Log.i(TAG, "NewPipeExtractor initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize NewPipeExtractor", e)
        }
    }
}
'@

$appPath = Join-Path $basePath "TicTubeApp.kt"
[System.IO.File]::WriteAllText($appPath, $appContent, $utf8NoBom)
Write-Host "  [OK] TicTubeApp.kt" -ForegroundColor Green

# ============================================================
# 3. MainScreen.kt
# ============================================================
$mainScreenContent = @'
package com.tictube

import android.util.Log
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
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

/**
 * Represents a single video result.
 * [videoUrl] is the YouTube page URL (e.g. https://www.youtube.com/watch?v=xxx),
 * NOT the direct stream URL.  Stream extraction happens in [PlayerScreen].
 */
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
    data class Success(val videos: List<VideoItem>) : UiState
    data class Error(val message: String) : UiState
}

// ─── ViewModel ────────────────────────────────────────────────

/**
 * Fetches real YouTube search results via NewPipeExtractor on [Dispatchers.IO].
 * Defaults to the query "Tech News" on first launch.
 */
class MainViewModel : ViewModel() {

    companion object {
        private const val TAG = "MainViewModel"
        private const val DEFAULT_QUERY = "Tech News"
        private const val MAX_RESULTS = 20
    }

    private val _uiState = MutableStateFlow<UiState>(UiState.Loading)
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        search(DEFAULT_QUERY)
    }

    /**
     * Performs a YouTube search and updates [uiState].
     * Safe to call from any thread — internally dispatches to IO.
     */
    fun search(query: String) {
        viewModelScope.launch {
            _uiState.value = UiState.Loading
            try {
                val videos = withContext(Dispatchers.IO) {
                    val extractor = ServiceList.YouTube.getSearchExtractor(query)
                    extractor.fetchPage()
                    extractor.initialPage.items
                        .filterIsInstance<StreamInfoItem>()
                        .take(MAX_RESULTS)
                        .map { item ->
                            VideoItem(
                                id = item.url,
                                title = item.name,
                                channel = item.uploaderName.orEmpty(),
                                durationText = formatDuration(item.duration),
                                thumbnailUrl = item.thumbnails
                                    .firstOrNull()?.url.orEmpty(),
                                videoUrl = item.url
                            )
                        }
                }
                if (videos.isEmpty()) {
                    _uiState.value = UiState.Error("No results found")
                } else {
                    _uiState.value = UiState.Success(videos)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Search failed for query: $query", e)
                _uiState.value = UiState.Error(
                    e.localizedMessage ?: "Search failed"
                )
            }
        }
    }

    /** Retries the last (default) query. */
    fun retry() = search(DEFAULT_QUERY)
}

// ─── Helpers ──────────────────────────────────────────────────

/**
 * Converts a duration in seconds to a human-readable string.
 * Negative values (used by NewPipeExtractor for live streams) return "LIVE".
 */
private fun formatDuration(seconds: Long): String {
    if (seconds < 0) return "LIVE"
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return if (h > 0) String.format("%d:%02d:%02d", h, m, s)
    else String.format("%d:%02d", m, s)
}

// ─── Composable ───────────────────────────────────────────────

/**
 * Main screen showing YouTube search results in a [ScalingLazyColumn]
 * with physical crown scrolling via [rotaryScrollable].
 *
 * Thumbnails are loaded with Coil [AsyncImage].
 * Loading / Error / Success states are rendered inside the column
 * so that the crown + position-indicator always remain functional.
 */
@Composable
fun MainScreen(
    viewModel: MainViewModel = viewModel(),
    onVideoClick: (VideoItem) -> Unit
) {
    val uiState by viewModel.uiState.collectAsState()
    val listState = rememberScalingLazyListState()
    val focusRequester = remember { FocusRequester() }

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
            when (val state = uiState) {

                is UiState.Loading -> {
                    item {
                        Box(
                            Modifier.fillMaxWidth().height(120.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                "Searching YouTube\u2026",
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
                                maxLines = 3,
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

                is UiState.Success -> {
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

    // Grab focus so the TicWatch crown immediately drives the list
    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }
}
'@

$mainScreenPath = Join-Path $basePath "MainScreen.kt"
[System.IO.File]::WriteAllText($mainScreenPath, $mainScreenContent, $utf8NoBom)
Write-Host "  [OK] MainScreen.kt" -ForegroundColor Green

# ============================================================
# 4. PlayerScreen.kt  (includes PlayerActivity)
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
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.VideoStream

// ─── Activity ─────────────────────────────────────────────────

/**
 * Hosts the video player.  Receives the YouTube *page* URL
 * (e.g. https://www.youtube.com/watch?v=xxx).
 * Stream extraction (getting the real .mp4 URL) happens inside
 * [PlayerScreen] on [Dispatchers.IO].
 */
class PlayerActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Start PlaybackService so ExoPlayer singleton is ready
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
        private const val TAG = "PlayerActivity"

        fun newIntent(context: Context, videoUrl: String, videoTitle: String): Intent {
            return Intent(context, PlayerActivity::class.java).apply {
                putExtra(EXTRA_VIDEO_URL, videoUrl)
                putExtra(EXTRA_VIDEO_TITLE, videoTitle)
            }
        }
    }
}

// ─── Stream extraction helper ─────────────────────────────────

/**
 * Uses NewPipeExtractor to resolve a YouTube page URL into a
 * direct playable stream URL.
 *
 * Strategy:
 *  1. Try muxed (video+audio) streams — pick closest to 360p
 *     which is ideal for a 1.43" watch display.
 *  2. Fallback to audio-only stream (highest bitrate) so the
 *     user at least gets audio when muxed is unavailable.
 *
 * Must be called on [Dispatchers.IO].
 */
private suspend fun extractStreamUrl(youtubeUrl: String): String {
    return withContext(Dispatchers.IO) {
        val extractor = ServiceList.YouTube.getStreamExtractor(youtubeUrl)
        extractor.fetchPage()

        // 1. Muxed streams (video + audio in one file)
        val muxedStreams: List<VideoStream> = try {
            extractor.videoStreams?.filter { it.isUrl } ?: emptyList()
        } catch (e: Exception) {
            Log.w("StreamExtract", "Could not get muxed streams", e)
            emptyList()
        }

        if (muxedStreams.isNotEmpty()) {
            // Prefer ~360p for the tiny watch screen
            val best = muxedStreams.minByOrNull { stream ->
                val res = stream.resolution
                    ?.replace(Regex("p.*"), "")
                    ?.toIntOrNull() ?: 999
                kotlin.math.abs(res - 360)
            }
            val url = best?.content
            if (!url.isNullOrBlank()) return@withContext url
        }

        // 2. Audio-only fallback (highest bitrate)
        val audioStreams = try {
            extractor.audioStreams?.filter { it.isUrl } ?: emptyList()
        } catch (e: Exception) {
            Log.w("StreamExtract", "Could not get audio streams", e)
            emptyList()
        }

        val bestAudio = audioStreams.maxByOrNull { it.averageBitrate }
        val audioUrl = bestAudio?.content
        if (!audioUrl.isNullOrBlank()) return@withContext audioUrl

        throw IllegalStateException("No playable streams found for this video")
    }
}

// ─── Composable ───────────────────────────────────────────────

/**
 * Full-screen player optimized for a round 1.43" Wear OS display.
 *
 * Lifecycle:
 *  1. Wait for [PlaybackService] to initialize ExoPlayer.
 *  2. Extract direct stream URL from YouTube page URL on IO thread.
 *  3. Feed extracted URL to ExoPlayer and begin playback.
 *
 * Crown: always bound to media volume via [onRotaryScrollEvent].
 * Controls: tap screen to toggle centered Play/Pause overlay (auto-hides 3s).
 */
@Composable
fun PlayerScreen(videoUrl: String, videoTitle: String) {
    val context       = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val audioManager  = remember {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    val focusRequester = remember { FocusRequester() }

    var showControls by remember { mutableStateOf(false) }
    var isPlaying    by remember { mutableStateOf(false) }
    var isLoading    by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var player       by remember { mutableStateOf(PlaybackService.player) }

    // ── Poll until PlaybackService has created the ExoPlayer ──
    LaunchedEffect(Unit) {
        while (player == null) {
            delay(100L)
            player = PlaybackService.player
        }
    }

    // ── Extract stream URL & start playback ──
    LaunchedEffect(player, videoUrl) {
        val p = player ?: return@LaunchedEffect
        if (videoUrl.isEmpty()) return@LaunchedEffect

        isLoading = true
        errorMessage = null

        try {
            val streamUrl = extractStreamUrl(videoUrl)
            // Back on Main thread — safe to touch the player
            p.setMediaItem(MediaItem.fromUri(streamUrl))
            p.prepare()
            p.playWhenReady = true
            isLoading = false
        } catch (e: Exception) {
            Log.e("PlayerScreen", "Stream extraction failed", e)
            isLoading = false
            errorMessage = e.localizedMessage ?: "Could not load video"
        }
    }

    // ── Auto-hide overlay after 3 seconds ──
    LaunchedEffect(showControls) {
        if (showControls) {
            delay(3000L)
            showControls = false
        }
    }

    // ── Sync isPlaying state from the actual Player ──
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }
        }
        player?.addListener(listener)
        onDispose { player?.removeListener(listener) }
    }

    // ── Lifecycle: re-sync on resume, keep audio alive on stop ──
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> {
                    player?.let { isPlaying = it.isPlaying }
                }
                else -> { /* Service keeps audio going in background */ }
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
        // ── Video surface (shown when not loading and no error) ──
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

        // ── Loading state ──
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

        // ── Error state ──
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
                    onClick = {
                        (context as? ComponentActivity)?.finish()
                    },
                    label = { Text("Back") },
                    colors = ChipDefaults.secondaryChipColors()
                )
            }
        }

        // ── Center play / pause overlay ──
        if (showControls && !isLoading && errorMessage == null && player != null) {
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
        }
    }

    // Grab focus so the crown drives volume immediately
    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }
}
'@

$playerScreenPath = Join-Path $basePath "PlayerScreen.kt"
[System.IO.File]::WriteAllText($playerScreenPath, $playerScreenContent, $utf8NoBom)
Write-Host "  [OK] PlayerScreen.kt (includes PlayerActivity)" -ForegroundColor Green

# ============================================================
# 5. PlaybackService.kt
# ============================================================
$playbackServiceContent = @'
package com.tictube

import android.content.Intent
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Background media playback service using Media3's [MediaSessionService].
 *
 * Architecture:
 * - Owns the single [ExoPlayer] instance, exposed via [Companion.player]
 *   for same-process access by [PlayerScreen].
 * - [MediaSession] lets the system route hardware media-button events
 *   and display Now Playing controls on the watch face.
 * - [C.WAKE_MODE_NETWORK] keeps CPU + WiFi alive while the screen is off
 *   so background audio streams continue uninterrupted.
 * - Audio focus is handled automatically by ExoPlayer.
 */
class PlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null

    companion object {
        /**
         * Direct reference to the ExoPlayer owned by this service.
         * Null when the service has not started or has been destroyed.
         */
        var player: ExoPlayer? = null
            private set
    }

    override fun onCreate() {
        super.onCreate()

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()

        val exoPlayer = ExoPlayer.Builder(this)
            .setAudioAttributes(audioAttributes, /* handleAudioFocus= */ true)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()

        player = exoPlayer
        mediaSession = MediaSession.Builder(this, exoPlayer).build()
    }

    override fun onGetSession(
        controllerInfo: MediaSession.ControllerInfo
    ): MediaSession? = mediaSession

    /**
     * When the user swipes the app from recents:
     * - If audio is actively playing, keep the service alive.
     * - Otherwise, stop to release resources.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = mediaSession?.player
        if (p == null || !p.playWhenReady || p.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        mediaSession?.run {
            player.release()
            release()
        }
        mediaSession = null
        Companion.player = null
        super.onDestroy()
    }
}
'@

$playbackServicePath = Join-Path $basePath "PlaybackService.kt"
[System.IO.File]::WriteAllText($playbackServicePath, $playbackServiceContent, $utf8NoBom)
Write-Host "  [OK] PlaybackService.kt" -ForegroundColor Green

# ============================================================
# Done
# ============================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " Phase 3 complete - 5 files generated            " -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Files written to:" -ForegroundColor White
Write-Host "  $downloaderPath"      -ForegroundColor Gray
Write-Host "  $appPath"             -ForegroundColor Gray
Write-Host "  $mainScreenPath"      -ForegroundColor Gray
Write-Host "  $playerScreenPath"    -ForegroundColor Gray
Write-Host "  $playbackServicePath" -ForegroundColor Gray
Write-Host ""
Write-Host "Next: run '.\build_apk.ps1' to compile." -ForegroundColor Yellow
Write-Host ""
Write-Host "What changed:" -ForegroundColor White
Write-Host "  - DownloaderImpl: HttpURLConnection bridge for NewPipeExtractor" -ForegroundColor Gray
Write-Host "  - TicTubeApp:     NewPipe.init(DownloaderImpl) on startup" -ForegroundColor Gray
Write-Host "  - MainScreen:     Real YouTube search (default: 'Tech News')" -ForegroundColor Gray
Write-Host "                    Coil AsyncImage thumbnails in Chips" -ForegroundColor Gray
Write-Host "  - PlayerScreen:   StreamExtractor resolves .mp4 URL on IO" -ForegroundColor Gray
Write-Host "                    Fallback to audio-only if no muxed streams" -ForegroundColor Gray
Write-Host "  - PlaybackService: Unchanged (already production-ready)" -ForegroundColor Gray
