# generate_ui.ps1
# TicTube Wear OS - Core UI & Media3 Code Generator
# Run from project root: S:\_Vibe_Coding\TicTube\WearApp
#
# Generates 4 files:
#   1. MainScreen.kt    - ScalingLazyColumn + rotary crown scrolling
#   2. PlayerScreen.kt  - Media3 ExoPlayer + rotary volume + PlayerActivity
#   3. PlaybackService.kt - MediaSessionService for background audio
#   4. MainActivity.kt  - Wear Navigation host

$ErrorActionPreference = "Stop"
$basePath = Join-Path $PSScriptRoot "app\src\main\java\com\tictube"

# Ensure target directory exists
if (-not (Test-Path $basePath)) {
    New-Item -ItemType Directory -Force -Path $basePath | Out-Null
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " TicTube - Generating Core UI & Player    " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. MainScreen.kt
# ============================================================
$mainScreenContent = @'
package com.tictube

import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.ViewModel
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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Represents a single video item in the search results list.
 * In the next phase, this will be populated by NewPipeExtractor.
 */
data class VideoItem(
    val id: String,
    val title: String,
    val channel: String,
    val durationText: String,
    val streamUrl: String = ""
)

/**
 * Mock ViewModel providing 5 dummy video entries for UI testing.
 * Will be replaced with actual NewPipeExtractor calls in the next phase.
 */
class MainViewModel : ViewModel() {
    private val _videos = MutableStateFlow(
        listOf(
            VideoItem(
                id = "dQw4w9WgXcQ",
                title = "Wear OS Development Tutorial 2024",
                channel = "Android Developers",
                durationText = "12:34",
                streamUrl = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
            ),
            VideoItem(
                id = "abc123",
                title = "TicWatch Pro 5 Enduro - Full Review",
                channel = "TechRadar",
                durationText = "8:21",
                streamUrl = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4"
            ),
            VideoItem(
                id = "def456",
                title = "Kotlin Coroutines & Flows Deep Dive",
                channel = "JetBrains",
                durationText = "45:00",
                streamUrl = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4"
            ),
            VideoItem(
                id = "ghi789",
                title = "Media3 ExoPlayer Migration Guide",
                channel = "Google Developers",
                durationText = "22:15",
                streamUrl = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4"
            ),
            VideoItem(
                id = "jkl012",
                title = "Building Compose UI for Wear OS",
                channel = "Android Devs",
                durationText = "15:47",
                streamUrl = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4"
            )
        )
    )
    val videos: StateFlow<List<VideoItem>> = _videos.asStateFlow()
}

/**
 * Main screen composable displaying a scrollable list of video results.
 *
 * Key Wear OS features:
 * - [ScalingLazyColumn] for proper round-screen scaling at list edges.
 * - [rotaryScrollable] modifier bound to FocusRequester so the TicWatch Pro 5
 *   physical rotating crown natively scrolls this list.
 * - [Scaffold] with [TimeText], [Vignette], and [PositionIndicator] for
 *   standard Wear OS chrome.
 */
@Composable
fun MainScreen(
    viewModel: MainViewModel = viewModel(),
    onVideoClick: (VideoItem) -> Unit
) {
    val videos by viewModel.videos.collectAsState()
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
            items(videos.size) { index ->
                val video = videos[index]
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
                    colors = ChipDefaults.secondaryChipColors(),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }

    // Request focus so the physical crown immediately drives the list
    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }
}
'@

$mainScreenPath = Join-Path $basePath "MainScreen.kt"
[System.IO.File]::WriteAllText($mainScreenPath, $mainScreenContent, $utf8NoBom)
Write-Host "  [OK] MainScreen.kt" -ForegroundColor Green

# ============================================================
# 2. PlayerScreen.kt  (includes PlayerActivity)
# ============================================================
$playerScreenContent = @'
package com.tictube

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay

/**
 * Activity hosting the video player.
 * Starts [PlaybackService] to ensure the [ExoPlayer] instance is available,
 * then renders [PlayerScreen] via Compose.
 */
class PlayerActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Ensure the PlaybackService is running so the ExoPlayer singleton is ready
        startService(Intent(this, PlaybackService::class.java))

        val videoUrl = intent.getStringExtra(EXTRA_VIDEO_URL).orEmpty()
        val videoTitle = intent.getStringExtra(EXTRA_VIDEO_TITLE).orEmpty()

        setContent {
            MaterialTheme {
                PlayerScreen(videoUrl = videoUrl, videoTitle = videoTitle)
            }
        }
    }

    companion object {
        const val EXTRA_VIDEO_URL = "extra_video_url"
        const val EXTRA_VIDEO_TITLE = "extra_video_title"

        /** Creates an Intent to launch the player for a given video. */
        fun newIntent(context: Context, videoUrl: String, videoTitle: String): Intent {
            return Intent(context, PlayerActivity::class.java).apply {
                putExtra(EXTRA_VIDEO_URL, videoUrl)
                putExtra(EXTRA_VIDEO_TITLE, videoTitle)
            }
        }
    }
}

/**
 * Full-screen video player composable optimized for a round 1.43" Wear OS display.
 *
 * Key features:
 * - Video surface via [AndroidView] wrapping Media3 [PlayerView], clipped to [CircleShape]
 *   to respect the round AMOLED boundary.
 * - Physical rotating crown is bound to media volume via [onRotaryScrollEvent].
 * - Tap anywhere to toggle a centered Play/Pause button overlay.
 * - Auto-hides controls after 3 seconds of inactivity.
 */
@Composable
fun PlayerScreen(videoUrl: String, videoTitle: String) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val audioManager = remember {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }
    val focusRequester = remember { FocusRequester() }

    var showControls by remember { mutableStateOf(true) }
    var isPlaying by remember { mutableStateOf(false) }
    var player by remember { mutableStateOf(PlaybackService.player) }

    // Poll until the service has initialized the ExoPlayer instance
    LaunchedEffect(Unit) {
        while (player == null) {
            delay(100L)
            player = PlaybackService.player
        }
    }

    // Set up the media item when the player becomes available
    LaunchedEffect(player, videoUrl) {
        player?.let { p ->
            if (videoUrl.isNotEmpty()) {
                p.setMediaItem(MediaItem.fromUri(videoUrl))
                p.prepare()
                p.playWhenReady = true
                isPlaying = true
            }
        }
    }

    // Auto-hide overlay controls after 3 seconds
    LaunchedEffect(showControls) {
        if (showControls) {
            delay(3000L)
            showControls = false
        }
    }

    // Listen for player state changes to keep isPlaying in sync
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }
        }
        player?.addListener(listener)
        onDispose {
            player?.removeListener(listener)
        }
    }

    // Pause on stop, resume on start (ambient mode / wrist-down)
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> {
                    // Player keeps running in PlaybackService for background audio.
                    // Video surface detaches automatically.
                }
                Lifecycle.Event.ON_START -> {
                    // Re-sync play state
                    player?.let { isPlaying = it.isPlaying }
                }
                else -> { /* no-op */ }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .clip(CircleShape)
            .background(Color.Black)
            .onRotaryScrollEvent { event ->
                // Crown controls media volume on the player screen
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
        // Video surface — Media3 PlayerView wrapped in AndroidView
        player?.let { exoPlayer ->
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        this.player = exoPlayer
                        useController = false               // We render our own controls
                        setKeepScreenOn(true)
                    }
                },
                update = { view ->
                    // Re-attach player if it changed (e.g. service restart)
                    view.player = exoPlayer
                },
                modifier = Modifier.fillMaxSize()
            )
        }

        // Loading indicator while waiting for service
        if (player == null) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    text = "Loading\u2026",
                    color = Color.White,
                    style = MaterialTheme.typography.body1
                )
            }
        }

        // Centered Play / Pause button overlay
        if (showControls && player != null) {
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

    // Immediately capture focus so the crown drives volume
    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }
}
'@

$playerScreenPath = Join-Path $basePath "PlayerScreen.kt"
[System.IO.File]::WriteAllText($playerScreenPath, $playerScreenContent, $utf8NoBom)
Write-Host "  [OK] PlayerScreen.kt (includes PlayerActivity)" -ForegroundColor Green

# ============================================================
# 3. PlaybackService.kt
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
 * - Owns the single [ExoPlayer] instance, exposed via [Companion.player] for
 *   same-process access by [PlayerScreen].
 * - Creates a [MediaSession] so the system (and Wear OS) can display media
 *   controls and route hardware button events.
 * - [C.WAKE_MODE_NETWORK] keeps the CPU and WiFi alive during background audio
 *   playback (screen off / wrist down).
 * - Handles audio focus automatically via [ExoPlayer.Builder.setAudioAttributes].
 */
class PlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null

    companion object {
        /**
         * Direct reference to the ExoPlayer owned by this service.
         * Safe for same-process, single-activity Wear OS apps.
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

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    /**
     * Called when the user swipes the app away from recents.
     * If nothing is playing, stop the service to free resources.
     * If audio is still playing, keep the service alive for background playback.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        val currentPlayer = mediaSession?.player
        if (currentPlayer == null ||
            !currentPlayer.playWhenReady ||
            currentPlayer.mediaItemCount == 0
        ) {
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
# 4. MainActivity.kt  (overwrites the dummy scaffold)
# ============================================================
$mainActivityContent = @'
package com.tictube

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController

/**
 * Root activity for TicTube.
 * Hosts the Wear OS navigation graph via [SwipeDismissableNavHost].
 * Currently has a single destination ("main"); additional screens
 * (Settings, Search History, etc.) can be added as new composable routes.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            TicTubeWearApp()
        }
    }
}

/**
 * Top-level Wear OS app composable.
 * Sets up the [SwipeDismissableNavHost] (standard Wear OS back navigation via swipe)
 * and routes video taps to [PlayerActivity] via explicit Intent.
 */
@Composable
fun TicTubeWearApp() {
    val context = LocalContext.current
    val navController = rememberSwipeDismissableNavController()

    MaterialTheme {
        SwipeDismissableNavHost(
            navController = navController,
            startDestination = "main"
        ) {
            composable("main") {
                MainScreen(
                    onVideoClick = { video ->
                        context.startActivity(
                            PlayerActivity.newIntent(
                                context = context,
                                videoUrl = video.streamUrl,
                                videoTitle = video.title
                            )
                        )
                    }
                )
            }
        }
    }
}
'@

$mainActivityPath = Join-Path $basePath "MainActivity.kt"
[System.IO.File]::WriteAllText($mainActivityPath, $mainActivityContent, $utf8NoBom)
Write-Host "  [OK] MainActivity.kt (overwritten)" -ForegroundColor Green

# ============================================================
# Done
# ============================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " All 4 files generated successfully!      " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Files written to:" -ForegroundColor White
Write-Host "  $mainScreenPath" -ForegroundColor Gray
Write-Host "  $playerScreenPath" -ForegroundColor Gray
Write-Host "  $playbackServicePath" -ForegroundColor Gray
Write-Host "  $mainActivityPath" -ForegroundColor Gray
Write-Host ""
Write-Host "Next step: run '.\build_apk.ps1' to compile." -ForegroundColor Yellow
