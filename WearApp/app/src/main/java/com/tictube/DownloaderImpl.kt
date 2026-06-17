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
 * [HttpURLConnection]. Zero external dependencies â€” no OkHttp needed.
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

        // Read response body â€” prefer inputStream, fall back to errorStream
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