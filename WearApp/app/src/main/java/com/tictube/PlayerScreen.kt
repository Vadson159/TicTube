package com.tictube

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
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
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.rotary.onRotaryScrollEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.FileDownloadDone
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.rounded.VolumeUp
import androidx.compose.material.icons.rounded.FastRewind
import androidx.compose.material.icons.rounded.FastForward
import androidx.wear.compose.material.Icon
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.ScalingLazyColumn
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.rememberScalingLazyListState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.StreamType

class PlayerActivity : ComponentActivity() {

    private var videoUrl = ""
    private var videoTitle = ""
    private var plUrls = arrayListOf<String>()
    private var plTitles = arrayListOf<String>()
    private var startIdx = 0
    private var playbackContext = PlaybackContext.SINGLE

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawableResource(android.R.color.transparent)
        startService(Intent(this, PlaybackService::class.java))
        if (!intent.getBooleanExtra("from_notification", false)) {
            PlaybackService.currentIntent = intent
        }
        parseIntent(intent)
        launchUi()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("from_notification", false)) return
        setIntent(intent)
        PlaybackService.currentIntent = intent
        parseIntent(intent)
        launchUi()
    }

    private fun parseIntent(intent: Intent) {
        val fromNotification = intent.getBooleanExtra("from_notification", false)
        if (fromNotification) {
            videoUrl = PlaybackService.currentVideoUrl
            videoTitle = PlaybackService.currentVideoTitle
            plUrls = ArrayList(PlaybackService.currentPlUrls)
            plTitles = ArrayList(PlaybackService.currentPlTitles)
            startIdx = PlaybackService.currentIdx
            playbackContext = runCatching { PlaybackContext.valueOf(PlaybackService.currentPlaybackContext) }.getOrDefault(PlaybackContext.SINGLE)
        } else {
            videoUrl = intent.getStringExtra(EXTRA_VIDEO_URL).orEmpty()
            videoTitle = intent.getStringExtra(EXTRA_VIDEO_TITLE).orEmpty()
            plUrls = intent.getStringArrayListExtra(EXTRA_PL_URLS) ?: arrayListOf()
            plTitles = intent.getStringArrayListExtra(EXTRA_PL_TITLES) ?: arrayListOf()
            startIdx = intent.getIntExtra(EXTRA_START_IDX, 0)
            playbackContext = runCatching {
                PlaybackContext.valueOf(intent.getStringExtra(EXTRA_PLAYBACK_CONTEXT).orEmpty())
            }.getOrElse {
                if (plUrls.isNotEmpty()) PlaybackContext.PLAYLIST else PlaybackContext.SINGLE
            }
            PlaybackService.currentVideoUrl = videoUrl
            PlaybackService.currentVideoTitle = videoTitle
            PlaybackService.currentPlUrls = plUrls
            PlaybackService.currentPlTitles = plTitles
            PlaybackService.currentIdx = startIdx
            PlaybackService.currentPlaybackContext = playbackContext.name
        }
    }

    private fun launchUi() {
        setContent { MaterialTheme {
            PlayerScreen(videoUrl, videoTitle, plUrls, plTitles, startIdx, playbackContext)
        }}
    }

    companion object {
        const val EXTRA_VIDEO_URL = "extra_video_url"
        const val EXTRA_VIDEO_TITLE = "extra_video_title"
        const val EXTRA_PL_URLS = "extra_pl_urls"
        const val EXTRA_PL_TITLES = "extra_pl_titles"
        const val EXTRA_START_IDX = "extra_start_idx"
        const val EXTRA_PLAYBACK_CONTEXT = "extra_playback_context"

        fun newIntent(ctx: Context, url: String, title: String, context: PlaybackContext = PlaybackContext.SINGLE) =
            Intent(ctx, PlayerActivity::class.java).apply {
                putExtra(EXTRA_VIDEO_URL, url)
                putExtra(EXTRA_VIDEO_TITLE, title)
                putExtra(EXTRA_PLAYBACK_CONTEXT, context.name)
            }

        fun newQueueIntent(ctx: Context, urls: ArrayList<String>, titles: ArrayList<String>, startIdx: Int, context: PlaybackContext) =
            Intent(ctx, PlayerActivity::class.java).apply {
                putStringArrayListExtra(EXTRA_PL_URLS, urls)
                putStringArrayListExtra(EXTRA_PL_TITLES, titles)
                putExtra(EXTRA_START_IDX, startIdx)
                putExtra(EXTRA_PLAYBACK_CONTEXT, context.name)
            }

        fun newPlaylistIntent(ctx: Context, urls: ArrayList<String>, titles: ArrayList<String>, startIdx: Int) =
            newQueueIntent(ctx, urls, titles, startIdx, PlaybackContext.PLAYLIST)
    }
}

private data class ExtractionResult(val streamUrl: String, val uploaderUrl: String, val uploaderName: String, val description: String, val isLive: Boolean)
data class CommentItem(val author: String, val text: String, val likes: Int, val date: String)
enum class DlState { IDLE, RUNNING, DONE, ERROR }
enum class PlaybackContext { SINGLE, FEED, CHANNEL, PLAYLIST, SHORTS }
private val SPEEDS = listOf(1.0f, 1.25f, 1.5f, 2.0f)
private const val SEEK_STEP_MS = 10_000L
private fun fmtSpeed(s: Float): String = if (s == s.toInt().toFloat()) "${s.toInt()}x" else "${s}x"
private fun Player.seekByMs(deltaMs: Long) {
    val upperBound = duration.takeIf { it > 0 } ?: Long.MAX_VALUE
    seekTo((currentPosition + deltaMs).coerceIn(0L, upperBound))
}
private fun playableMediaItem(uri: String, title: String, isLive: Boolean = false): MediaItem {
    val builder = MediaItem.Builder()
        .setUri(uri)
        .setMediaMetadata(MediaMetadata.Builder().setTitle(title.ifBlank { "TicTube" }).build())
    if (isLive) builder.setMimeType(MimeTypes.APPLICATION_M3U8)
    return builder.build()
}

private suspend fun extract(ytUrl: String, q: SettingsManager.StreamQuality): ExtractionResult =
    withContext(Dispatchers.IO) {
        val ext = ServiceList.YouTube.getStreamExtractor(ytUrl); ext.fetchPage()
        val uUrl = ext.uploaderUrl.orEmpty(); val uName = ext.uploaderName.orEmpty(); val desc = try { ext.description?.content.orEmpty() } catch (_: Exception) { "" }; val sType = ext.streamType
        val isLive = sType == StreamType.LIVE_STREAM || sType == StreamType.AUDIO_LIVE_STREAM; var url: String? = null
        if (isLive) { url = try { ext.hlsUrl } catch (_: Exception) { null } }
        if (url.isNullOrBlank()) {
            val targetRes = when (q) { SettingsManager.StreamQuality.AUDIO_ONLY -> 0; SettingsManager.StreamQuality.Q360P -> 360; SettingsManager.StreamQuality.Q480P -> 480; SettingsManager.StreamQuality.Q720P -> 720; SettingsManager.StreamQuality.Q1080P -> 1080 }
            if (targetRes > 0) { val muxed = try { ext.videoStreams?.filter { it.isUrl } ?: emptyList() } catch (_: Exception) { emptyList() }; url = muxed.minByOrNull { s -> val r = s.resolution?.replace(Regex("p.*"), "")?.toIntOrNull() ?: 999; kotlin.math.abs(r - targetRes) }?.content }
            if (url.isNullOrBlank()) { val audio = try { ext.audioStreams?.filter { it.isUrl } ?: emptyList() } catch (_: Exception) { emptyList() }; url = audio.maxByOrNull { it.averageBitrate }?.content }
        }
        if (url.isNullOrBlank()) throw IllegalStateException("No playable streams")
        ExtractionResult(url, uUrl, uName, desc, isLive)
    }

private suspend fun loadComments(ytUrl: String): List<CommentItem> = withContext(Dispatchers.IO) {
    try { val ce = ServiceList.YouTube.getCommentsExtractor(ytUrl); ce.fetchPage(); ce.initialPage.items.take(20).map { c -> CommentItem(c.uploaderName.orEmpty(), c.commentText?.content?.replace(Regex("<[^>]*>"), "").orEmpty(), c.likeCount, c.textualUploadDate.orEmpty()) } } catch (e: Exception) { emptyList() }
}

@Composable
fun PlayerScreen(
    videoUrl: String,
    videoTitle: String,
    plUrls: List<String> = emptyList(),
    plTitles: List<String> = emptyList(),
    startIdx: Int = 0,
    playbackContext: PlaybackContext = PlaybackContext.SINGLE
) {
    val ctx = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val audioMgr = remember { ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    val dlMgr = remember { DownloadManager.getInstance(ctx.applicationContext) }
    val histMgr = remember { HistoryManager.getInstance(ctx.applicationContext) }
    val settMgr = remember { SettingsManager.getInstance(ctx.applicationContext) }
    val scope = rememberCoroutineScope()

    val isPlaylist = plUrls.isNotEmpty()
    val isShorts = playbackContext == PlaybackContext.SHORTS
    var curIdx by remember { mutableIntStateOf(startIdx) }
    LaunchedEffect(curIdx) { PlaybackService.currentIdx = curIdx }
    val curUrl = if (isPlaylist) plUrls.getOrElse(curIdx) { videoUrl } else videoUrl
    val curTitle = if (isPlaylist) plTitles.getOrElse(curIdx) { videoTitle } else videoTitle
    var resolvedTitle by remember { mutableStateOf(curTitle) }
    val isLocal = if (curUrl.isNotEmpty()) curUrl.startsWith("file://") || curUrl.startsWith("/") else PlaybackService.currentIsLocal
    val pageCount = if (isLocal) 1 else 2

    var showCtrls by remember { mutableStateOf(false) }
    var isPlaying by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(true) }
    var errorMsg by remember { mutableStateOf<String?>(null) }
    var player by remember { mutableStateOf(PlaybackService.player) }
    var upUrl by remember { mutableStateOf(PlaybackService.currentUpUrl) }; var isLiked by remember { mutableStateOf(PlaybackService.currentIsLiked) }; var desc by remember { mutableStateOf("") }; var comments by remember { mutableStateOf<List<CommentItem>>(emptyList()) }; var extractedUrl by remember { mutableStateOf(PlaybackService.currentExtractedUrl) }; var dlState by remember { mutableStateOf(DlState.IDLE) }; var downloadJob by remember { mutableStateOf<Job?>(null) }; var activeDownloadKey by remember { mutableStateOf<String?>(null) }; var speed by remember { mutableFloatStateOf(PlaybackService.player?.playbackParameters?.speed ?: 1.0f) }; var isLive by remember { mutableStateOf(PlaybackService.currentIsLive) }

    val volFocus = remember { FocusRequester() }
    val infoFocus = remember { FocusRequester() }
    val pagerState = rememberPagerState(pageCount = { if (isShorts || isLocal) 1 else pageCount })

    fun playNextInQueue() {
        if (curIdx < plUrls.size - 1) curIdx++
    }

    LaunchedEffect(Unit) { while (player == null) { delay(100); player = PlaybackService.player } }

    LaunchedEffect(player, curUrl) {
        val p = player ?: return@LaunchedEffect
        if (curUrl.isEmpty()) {
            if (p.currentMediaItem != null) { 
                isLoading = false; showCtrls = true; isPlaying = p.isPlaying 
                resolvedTitle = p.currentMediaItem?.mediaMetadata?.title?.toString() ?: "Now Playing"
            }
            return@LaunchedEffect
        }
        
        if (curUrl == PlaybackService.currentVideoUrl && p.currentMediaItem != null && (isLocal || extractedUrl.isNotBlank())) {
            isLoading = false
            showCtrls = true
            isPlaying = p.isPlaying
            resolvedTitle = curTitle
            return@LaunchedEffect
        }
        
        PlaybackService.currentVideoUrl = curUrl
        isLoading = true; errorMsg = null; dlState = DlState.IDLE; activeDownloadKey = null; desc = ""; comments = emptyList(); extractedUrl = ""; upUrl = ""; isLive = false; isLiked = false
        PlaybackService.currentExtractedUrl = ""; PlaybackService.currentUpUrl = ""; PlaybackService.currentIsLive = false; PlaybackService.currentIsLiked = false
        try {
            if (isLocal) {
                p.setMediaItem(playableMediaItem(curUrl, curTitle)); p.prepare(); p.playWhenReady = true
                isLoading = false; showCtrls = true
                PlaybackService.currentIsLocal = true
            } else {
                val result = extract(curUrl, settMgr.getQuality())
                extractedUrl = result.streamUrl; upUrl = result.uploaderUrl
                desc = result.description.replace(Regex("<[^>]*>"), "").trim(); isLive = result.isLive
                resolvedTitle = curTitle
                PlaybackService.currentExtractedUrl = extractedUrl
                PlaybackService.currentUpUrl = upUrl
                PlaybackService.currentIsLive = isLive
                PlaybackService.currentIsLocal = false

                val mediaItem = playableMediaItem(result.streamUrl, curTitle, result.isLive)
                p.setMediaItem(mediaItem); p.prepare()
                
                if (!isLocal && !result.isLive) {
                    val savedPos = histMgr.getAll().find { it.url == curUrl }?.positionMs ?: 0L
                    if (savedPos > 0L) p.seekTo(savedPos)
                }
                
                p.playWhenReady = true
                if (result.isLive) { speed = 1.0f; p.setPlaybackSpeed(1.0f) } else { p.setPlaybackSpeed(speed) }
                isLoading = false; showCtrls = true
            }
        } catch (e: Exception) { Log.e("Player", "extract", e); isLoading = false; errorMsg = e.localizedMessage ?: "Could not load video" }
    }

    LaunchedEffect(curUrl) { if (!isLocal && curUrl.isNotEmpty()) comments = loadComments(curUrl) }
    LaunchedEffect(showCtrls) { if (showCtrls) { delay(5000); showCtrls = false } }
    
    LaunchedEffect(player, curUrl) {
        while (true) {
            delay(5000)
            player?.let { p ->
                if (p.isPlaying && !isLive && !isLocal && curUrl.isNotBlank()) {
                    histMgr.add(curUrl, curTitle, p.currentPosition)
                }
            }
        }
    }

    DisposableEffect(player, playbackContext, curIdx, plUrls.size) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(p: Boolean) { isPlaying = p }
            override fun onPlaybackStateChanged(state: Int) {
                if (state != Player.STATE_ENDED) return
                if (playbackContext == PlaybackContext.SHORTS) {
                    player?.seekTo(0)
                    player?.playWhenReady = true
                    player?.play()
                } else if (isPlaylist) {
                    playNextInQueue()
                }
            }
        }
        player?.addListener(listener)
        onDispose { player?.removeListener(listener) }
    }

    DisposableEffect(lifecycleOwner) {
        val obs = LifecycleEventObserver { _, ev -> if (ev == Lifecycle.Event.ON_START) player?.let { isPlaying = it.isPlaying } }
        lifecycleOwner.lifecycle.addObserver(obs)
        onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
    }

    LaunchedEffect(pagerState.currentPage) {
        delay(50)
        runCatching { if (pagerState.currentPage == 0) volFocus.requestFocus() else infoFocus.requestFocus() }
    }

    Box(Modifier.fillMaxSize().clip(CircleShape).background(Color.Black)) {
        VerticalPager(
            state = pagerState,
            modifier = Modifier.fillMaxSize(),
            userScrollEnabled = !isShorts
        ) { page ->
            when (page) {
                0 -> PlayerPage(
                    player = player, isLoading = isLoading, errorMsg = errorMsg, isPlaying = isPlaying, showCtrls = showCtrls,
                    curTitle = resolvedTitle, upUrl = upUrl, isLiked = isLiked, extractedUrl = extractedUrl, dlState = dlState, speed = speed,
                    isLocal = isLocal, isLive = isLive, isPlaylist = isPlaylist, isShorts = isShorts, curIdx = curIdx, totalTracks = plUrls.size,
                    audioMgr = audioMgr, focusReq = volFocus,
                    onTap = { showCtrls = !showCtrls },
                    onPlayPause = { player?.let { if (it.isPlaying) it.pause() else it.play() } },
                    onLike = { isLiked = !isLiked; PlaybackService.currentIsLiked = isLiked; showCtrls = true },
                    onDownload = {
                        if (extractedUrl.isNotBlank()) {
                            val stream = extractedUrl
                            val title = resolvedTitle
                            val downloadKey = "$stream\n$title"
                            when (dlState) {
                                DlState.RUNNING -> {
                                    downloadJob?.cancel()
                                    dlMgr.deleteBySource(stream, title)
                                    downloadJob = null
                                    activeDownloadKey = null
                                    dlState = DlState.IDLE
                                }
                                DlState.DONE -> {
                                    dlMgr.deleteBySource(stream, title)
                                    activeDownloadKey = null
                                    dlState = DlState.IDLE
                                }
                                DlState.IDLE, DlState.ERROR -> {
                                    dlState = DlState.RUNNING
                                    activeDownloadKey = downloadKey
                                    var job: Job? = null
                                    job = scope.launch {
                                        try {
                                            dlMgr.download(stream, title)
                                            if (downloadJob == job && activeDownloadKey == downloadKey) dlState = DlState.DONE
                                        } catch (e: kotlinx.coroutines.CancellationException) {
                                            dlMgr.deleteBySource(stream, title)
                                            if (downloadJob == job && activeDownloadKey == downloadKey) dlState = DlState.IDLE
                                        } catch (e: Exception) {
                                            if (downloadJob == job && activeDownloadKey == downloadKey) dlState = DlState.ERROR
                                        } finally {
                                            if (downloadJob == job && activeDownloadKey == downloadKey) {
                                                downloadJob = null
                                                activeDownloadKey = null
                                            }
                                        }
                                    }
                                    downloadJob = job
                                }
                            }
                            showCtrls = true
                        }
                    },
                    onCycleSpeed = { val next = SPEEDS[(SPEEDS.indexOf(speed) + 1) % SPEEDS.size]; speed = next; player?.setPlaybackSpeed(next); showCtrls = true },
                    onSkipNext = { playNextInQueue() },
                    onSwipeUp = { if (isShorts) playNextInQueue() else if (pageCount > 1) scope.launch { pagerState.animateScrollToPage(1) } },
                    onOpenInfo = { if (pageCount > 1) scope.launch { pagerState.animateScrollToPage(1) } },
                    onFinish = { (ctx as? ComponentActivity)?.finish() }
                )
                1 -> InfoPage(resolvedTitle, desc, comments, infoFocus)
            }
        }

        if (!isShorts && pageCount > 1) { Column(Modifier.align(Alignment.CenterEnd).padding(end = 4.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) { repeat(pageCount) { idx -> Box(Modifier.size(4.dp).clip(CircleShape).background(if (idx == pagerState.currentPage) Color.White else Color.Gray.copy(0.4f))) } } }
    }
}

@Composable
private fun PlayerPage(
    player: androidx.media3.exoplayer.ExoPlayer?, isLoading: Boolean, errorMsg: String?,
    isPlaying: Boolean, showCtrls: Boolean, curTitle: String, upUrl: String, isLiked: Boolean,
    extractedUrl: String, dlState: DlState, speed: Float, isLocal: Boolean, isLive: Boolean,
    isPlaylist: Boolean, isShorts: Boolean, curIdx: Int, totalTracks: Int,
    audioMgr: AudioManager, focusReq: FocusRequester,
    onTap: () -> Unit, onPlayPause: () -> Unit, onLike: () -> Unit, onDownload: () -> Unit, onCycleSpeed: () -> Unit, onSkipNext: () -> Unit, onSwipeUp: () -> Unit, onOpenInfo: () -> Unit, onFinish: () -> Unit
) {
    var curVol by remember { mutableIntStateOf(audioMgr.getStreamVolume(AudioManager.STREAM_MUSIC)) }
    val maxVol = remember { audioMgr.getStreamMaxVolume(AudioManager.STREAM_MUSIC) }
    var showVolIndicator by remember { mutableStateOf(false) }

    var scrollAccum by remember { mutableFloatStateOf(0f) }
    val scrollThreshold = 80f

    LaunchedEffect(showVolIndicator) { if (showVolIndicator) { delay(1500); showVolIndicator = false } }

    var resizeMode by remember { mutableIntStateOf(androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT) }
    var rewindIndicator by remember { mutableIntStateOf(0) }

    LaunchedEffect(rewindIndicator) {
        if (rewindIndicator != 0) {
            delay(800)
            rewindIndicator = 0
        }
    }

    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black)
            .onRotaryScrollEvent { ev ->
                scrollAccum += ev.verticalScrollPixels
                if (abs(scrollAccum) >= scrollThreshold) {
                    val dir = if (scrollAccum > 0f) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER
                    audioMgr.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, 0)
                    curVol = audioMgr.getStreamVolume(AudioManager.STREAM_MUSIC)
                    scrollAccum = 0f
                }
                showVolIndicator = true
                true
            }.focusRequester(focusReq).focusable()
            .pointerInput(player) {
                detectTapGestures(
                    onTap = { onTap() },
                    onDoubleTap = { tap ->
                        val third = size.width / 3f
                        when {
                            tap.x < third -> { player?.seekByMs(-SEEK_STEP_MS); rewindIndicator = -1 }
                            tap.x > third * 2f -> { player?.seekByMs(SEEK_STEP_MS); rewindIndicator = 1 }
                            else -> {
                                resizeMode = if (resizeMode == androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT) {
                                    androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                                } else {
                                    androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
                                }
                            }
                        }
                    }
                )
            }
            .pointerInput(isShorts, curIdx, totalTracks) {
                if (!isShorts) return@pointerInput
                var dragY = 0f
                detectVerticalDragGestures(
                    onDragStart = { dragY = 0f },
                    onVerticalDrag = { change, amount ->
                        dragY += amount
                        change.consume()
                    },
                    onDragEnd = {
                        val verticalThreshold = size.height * 0.18f
                        if (-dragY > verticalThreshold) {
                            onSwipeUp()
                        }
                    }
                )
            },
        contentAlignment = Alignment.Center
    ) {
        if (!isLoading && errorMsg == null) {
            player?.let { exo ->
                AndroidView(
                    factory = { c -> PlayerView(c).apply { 
                        this.player = exo
                        useController = false
                        isClickable = false
                        isFocusable = false
                        setKeepScreenOn(true)
                        this.resizeMode = resizeMode 
                        clipToOutline = true
                        outlineProvider = object : android.view.ViewOutlineProvider() {
                            override fun getOutline(view: android.view.View, outline: android.graphics.Outline) {
                                outline.setOval(0, 0, view.width, view.height)
                            }
                        }
                    }},
                    update = { it.player = player; it.resizeMode = resizeMode },
                    modifier = Modifier
                        .fillMaxSize()
                )
            }
        }

        if (rewindIndicator != 0) {
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.3f))) {
                val align = if (rewindIndicator == -1) Alignment.CenterStart else Alignment.CenterEnd
                val icon = if (rewindIndicator == -1) Icons.Rounded.FastRewind else Icons.Rounded.FastForward
                val text = if (rewindIndicator == -1) "-10s" else "+10s"
                Column(Modifier.align(align).padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(icon, null, tint = Color.White, modifier = Modifier.size(32.dp))
                    Text(text, color = Color.White, style = MaterialTheme.typography.caption2)
                }
            }
        }

        if (isLive && !isLoading && errorMsg == null) { Text("\uD83D\uDD34 LIVE", color = Color(0xFFFF4444), style = MaterialTheme.typography.caption2, modifier = Modifier.align(Alignment.TopCenter).padding(top = 18.dp)) }

        if (showVolIndicator) {
            CircularProgressIndicator(progress = curVol.toFloat() / maxVol.toFloat(), modifier = Modifier.fillMaxSize(), strokeWidth = 3.dp, indicatorColor = Color(0xFFCC0000), trackColor = Color.Transparent)
            Icon(Icons.Rounded.VolumeUp, null, tint = Color.White.copy(alpha = 0.8f), modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp).size(20.dp))
        }

        if (isLoading) Column(horizontalAlignment = Alignment.CenterHorizontally) { CircularProgressIndicator(indicatorColor = Color(0xFFCC0000), trackColor = Color.DarkGray, modifier = Modifier.size(48.dp)); Spacer(Modifier.height(12.dp)); Text("Loading\u2026", color = Color.White, style = MaterialTheme.typography.body1); Spacer(Modifier.height(4.dp)); Text(curTitle, color = Color.Gray, style = MaterialTheme.typography.caption3, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp)) }
        if (errorMsg != null) Column(horizontalAlignment = Alignment.CenterHorizontally) { Icon(Icons.Rounded.Warning, null, tint = Color(0xFFFF6B6B), modifier = Modifier.size(32.dp)); Spacer(Modifier.height(4.dp)); Text("Error", color = Color(0xFFFF6B6B), style = MaterialTheme.typography.title3); Spacer(Modifier.height(4.dp)); Text(errorMsg, color = Color.White, style = MaterialTheme.typography.caption3, maxLines = 3, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp)); Spacer(Modifier.height(8.dp)); Chip(onClick = onFinish, label = { Text("Back") }, colors = ChipDefaults.secondaryChipColors()) }

        if (showCtrls && !isLoading && errorMsg == null && player != null) {
            Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.6f))) {
                Column(modifier = Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (isPlaylist) Text("${curIdx + 1}/$totalTracks", color = Color.White.copy(0.7f), style = MaterialTheme.typography.caption3)
                    Button(onClick = onPlayPause, modifier = Modifier.size(ButtonDefaults.LargeButtonSize), colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFCC0000))) { Icon(if (isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow, null, tint = Color.White) }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (upUrl.isNotEmpty() && !isLocal) CompactChip(onClick = onLike, label = { Icon(if (isLiked) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder, null, modifier = Modifier.size(16.dp)) }, colors = if (isLiked) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors())
                        if (!isLocal && !isLive && extractedUrl.isNotBlank()) CompactChip(onClick = onDownload, label = { Icon(when (dlState) { DlState.IDLE -> Icons.Rounded.Download; DlState.RUNNING -> Icons.Rounded.Speed; DlState.DONE -> Icons.Rounded.FileDownloadDone; DlState.ERROR -> Icons.Rounded.Warning }, null, modifier = Modifier.size(16.dp)) }, colors = if (dlState == DlState.RUNNING || dlState == DlState.DONE) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors())
                        if (isPlaylist && !isShorts) CompactChip(onClick = onSkipNext, label = { Icon(Icons.Rounded.SkipNext, null, modifier = Modifier.size(16.dp)) }, colors = ChipDefaults.secondaryChipColors())
                    }
                    if (!isLive) CompactChip(onClick = onCycleSpeed, label = { Text(fmtSpeed(speed), maxLines = 1) }, icon = { Icon(Icons.Rounded.Speed, null, modifier = Modifier.size(14.dp)) }, colors = ChipDefaults.secondaryChipColors())
                }
            }
        }
    }
}

@Composable
private fun InfoPage(title: String, desc: String, comments: List<CommentItem>, focusReq: FocusRequester) {
    val listState = rememberScalingLazyListState()
    Scaffold(positionIndicator = { PositionIndicator(scalingLazyListState = listState) }) {
        ScalingLazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .rotaryScrollable(behavior = RotaryScrollableDefaults.behavior(listState), focusRequester = focusReq)
                .focusRequester(focusReq)
                .focusable()
        ) {
            item { Text(title, style = MaterialTheme.typography.title3, color = Color.White, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)) }
            if (desc.isNotBlank()) { item { Spacer(Modifier.height(8.dp)) }; item { Text(desc.take(1000), style = MaterialTheme.typography.body2, color = Color.LightGray, modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp)) } }
            item { Spacer(Modifier.height(12.dp)) }
            item { Text("\uD83D\uDCAC Comments (${comments.size})", style = MaterialTheme.typography.title3, color = Color.White, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)) }
            if (comments.isEmpty()) { item { Text("No comments available", color = Color.Gray, style = MaterialTheme.typography.body2, modifier = Modifier.padding(horizontal = 12.dp)) } } else {
                items(comments.size) { i -> val c = comments[i]
                    Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
                        Text(c.author, style = MaterialTheme.typography.caption1, color = Color.Cyan, maxLines = 1)
                        Text(c.text.take(300), style = MaterialTheme.typography.body2, color = Color.White, maxLines = 6, overflow = TextOverflow.Ellipsis)
                        Text("\u2764 ${c.likes}  \u2022  ${c.date}", style = MaterialTheme.typography.caption3, color = Color.Gray)
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}
