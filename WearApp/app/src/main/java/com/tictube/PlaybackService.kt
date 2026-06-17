package com.tictube

import android.app.Notification
import android.app.PendingIntent
import android.app.TaskStackBuilder
import android.content.Intent
import android.content.pm.ServiceInfo
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class PlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null
    private var playerListener: Player.Listener? = null
    private lateinit var notificationManager: NotificationManager
    private var wifiLock: android.net.wifi.WifiManager.WifiLock? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var connectivityManager: ConnectivityManager? = null

    companion object {
        private const val CHANNEL_ID = "tictube_media"
        private const val NOTIFICATION_ID = 1001

        var player: ExoPlayer? = null
            private set
        var currentIntent: Intent? = null
        var currentExtractedUrl: String = ""
        var currentUpUrl: String = ""
        var currentIsLiked: Boolean = false
        var currentIsLive: Boolean = false
        var currentIsLocal: Boolean = false

        var currentVideoUrl: String = ""
        var currentVideoTitle: String = ""
        var currentPlUrls: List<String> = emptyList()
        var currentPlTitles: List<String> = emptyList()
        var currentIdx: Int = 0
        var currentPlaybackContext: String = "SINGLE"
    }

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(NotificationManager::class.java)
        ensureNotificationChannel()

        val wifiManager = getSystemService(android.content.Context.WIFI_SERVICE) as android.net.wifi.WifiManager
        wifiLock = wifiManager.createWifiLock(android.net.wifi.WifiManager.WIFI_MODE_FULL_HIGH_PERF, "TicTube:PlaybackWifiLock")
        wifiLock?.acquire()

        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
            
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {}
        }
        connectivityManager?.requestNetwork(request, networkCallback!!)

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                25000, 
                50000, 
                1000, 
                1500  
            ).build()

        val exoPlayer = ExoPlayer.Builder(this)
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .setLoadControl(loadControl)
            .build()

        player = exoPlayer
        playerListener = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                updatePlaybackNotification()
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                updatePlaybackNotification()
            }

            override fun onMediaMetadataChanged(mediaMetadata: MediaMetadata) {
                updatePlaybackNotification()
            }
        }
        exoPlayer.addListener(playerListener!!)

        val intent = Intent(this, PlayerActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("from_notification", true)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        mediaSession = MediaSession.Builder(this, exoPlayer)
            .setSessionActivity(pendingIntent)
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = mediaSession?.player
        if (p == null || !p.playWhenReady || p.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        playerListener?.let { listener -> player?.removeListener(listener) }
        stopForeground(STOP_FOREGROUND_REMOVE)
        notificationManager.cancel(NOTIFICATION_ID)
        wifiLock?.takeIf { it.isHeld }?.release()
        networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        mediaSession?.run {
            player.release()
            release()
        }
        mediaSession = null
        Companion.player = null
        super.onDestroy()
    }

    private fun ensureNotificationChannel() {
        if (notificationManager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(CHANNEL_ID, "Media Playback", NotificationManager.IMPORTANCE_DEFAULT)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun updatePlaybackNotification() {
        val p = player ?: return
        if (p.currentMediaItem == null || p.playbackState == Player.STATE_IDLE) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            notificationManager.cancel(NOTIFICATION_ID)
            return
        }

        val notification = buildPlaybackNotification(p)
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        )
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildPlaybackNotification(p: Player): Notification {
        val title = p.mediaMetadata.title?.toString()
            ?.takeIf { it.isNotBlank() }
            ?: p.currentMediaItem?.mediaMetadata?.title?.toString()
                ?.takeIf { it.isNotBlank() }
            ?: "TicTube"
        val stateText = if (p.isPlaying) "Playing in background" else "Paused"
        val intent = Intent(this, PlayerActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("from_notification", true)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText("$stateText - tap to return")
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(p.isPlaying)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
    }
}
