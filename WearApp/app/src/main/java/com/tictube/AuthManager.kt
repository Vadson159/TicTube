package com.tictube

import android.accounts.Account
import android.content.Context
import android.util.Log
import com.google.android.gms.auth.GoogleAuthUtil
import com.google.android.gms.auth.UserRecoverableAuthException
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.common.api.Scope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AuthManager private constructor(private val context: Context) {
    
    companion object {
        private const val TAG = "AuthManager"
        const val YOUTUBE_READONLY_SCOPE = "https://www.googleapis.com/auth/youtube.readonly"
        const val SCOPE = "oauth2:$YOUTUBE_READONLY_SCOPE"

        @Volatile private var instance: AuthManager? = null
        fun getInstance(ctx: Context): AuthManager =
            instance ?: synchronized(this) {
                instance ?: AuthManager(ctx.applicationContext).also { instance = it }
            }
    }

    private val settings = SettingsManager.getInstance(context)
    @Volatile var lastError: String? = null
        private set

    suspend fun getAccessToken(forceRefresh: Boolean = false): String? = withContext(Dispatchers.IO) {
        lastError = null
        val account = resolveAccount() ?: return@withContext null

        try {
            var token = GoogleAuthUtil.getToken(context, account, SCOPE)
            if (forceRefresh) {
                GoogleAuthUtil.clearToken(context, token)
                token = GoogleAuthUtil.getToken(context, account, SCOPE)
            }
            return@withContext token
        } catch (e: UserRecoverableAuthException) {
            lastError = "YouTube permission needs reconnect"
            Log.w(TAG, "User action required for YouTube token", e)
        } catch (e: Exception) {
            lastError = e.localizedMessage ?: "Could not get Google token"
            Log.w(TAG, "Could not get Google token", e)
        }
        return@withContext null
    }

    suspend fun invalidateToken(token: String) = withContext(Dispatchers.IO) {
        try {
            GoogleAuthUtil.clearToken(context, token)
        } catch (e: Exception) {
            Log.w(TAG, "Could not clear cached Google token", e)
        }
    }

    private fun resolveAccount(): Account? {
        val signedIn = GoogleSignIn.getLastSignedInAccount(context)
        if (signedIn != null && !GoogleSignIn.hasPermissions(signedIn, Scope(YOUTUBE_READONLY_SCOPE))) {
            lastError = "YouTube permission is not granted"
            return null
        }

        signedIn?.account?.let { return it }
        val email = signedIn?.email?.takeIf { it.isNotBlank() } ?: settings.accountName
        return email.takeIf { it.isNotBlank() }?.let { Account(it, "com.google") }
    }
}
