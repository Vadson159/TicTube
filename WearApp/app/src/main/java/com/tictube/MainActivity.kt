package com.tictube

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController

class MainActivity : ComponentActivity() {
    private var wifiLock: android.net.wifi.WifiManager.WifiLock? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var connectivityManager: ConnectivityManager? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val wifiManager = getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
        wifiLock = wifiManager.createWifiLock(android.net.wifi.WifiManager.WIFI_MODE_FULL_HIGH_PERF, "TicTube:MainWifiLock")
        
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
            
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                // Wi-Fi radio is requested and active
            }
        }
        connectivityManager?.requestNetwork(request, networkCallback!!)

        setContent { TicTubeWearApp() }
    }

    override fun onResume() {
        super.onResume()
        wifiLock?.acquire()
    }

    override fun onPause() {
        super.onPause()
        wifiLock?.takeIf { it.isHeld }?.release()
    }

    override fun onDestroy() {
        networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        super.onDestroy()
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