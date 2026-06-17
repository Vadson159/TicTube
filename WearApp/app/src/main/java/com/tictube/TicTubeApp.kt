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