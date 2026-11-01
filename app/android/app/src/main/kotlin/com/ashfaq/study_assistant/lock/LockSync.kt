package com.ashfaq.study_assistant.lock

import android.app.AppOpsManager
import android.content.Context
import android.os.Build
import android.os.Process
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** Talks to the server from native code, so locks stay current with the app closed. */
object LockSync {
    private const val TAG = "LockSync"
    private const val APPS_EVERY_MS = 6 * 60 * 60 * 1000L

    sealed interface Result {
        data class Updated(val state: LockState) : Result
        /** The device token was rejected: the phone is no longer registered. */
        data object Unregistered : Result
        data object Failed : Result
    }

    /** How often the discovery file may be read while the server is unreachable. */
    private const val DISCOVERY_GAP_MS = 2 * 60 * 1000L

    /**
     * Sends a heartbeat and stores the lock state it returns. Blocking: call off the main thread.
     * If the server can't be reached and its address may have changed (a tunnel restarted while the
     * app was closed), the address is looked up again and the heartbeat retried once.
     */
    fun heartbeat(context: Context, store: LockStore, protectionOn: Boolean): Result {
        val base = store.apiBaseUrl ?: return Result.Failed
        val token = store.deviceToken ?: return Result.Failed
        heartbeatAt(context, store, protectionOn, base, token)?.let { return it }
        val moved = rediscover(store) ?: return Result.Failed
        return heartbeatAt(context, store, protectionOn, moved, token) ?: Result.Failed
    }

    /** Reads the discovery file. Returns the new address if it changed, else null. */
    private fun rediscover(store: LockStore): String? {
        val discovery = store.discoveryUrl ?: return null
        val now = System.currentTimeMillis()
        if (now - store.lastDiscoveryAt < DISCOVERY_GAP_MS) return null
        store.lastDiscoveryAt = now
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL("$discovery?t=$now").openConnection() as HttpURLConnection).apply {
                connectTimeout = 8_000
                readTimeout = 8_000
            }
            if (connection.responseCode !in 200..299) return null
            val url = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
                .optString("apiBaseUrl").trimEnd('/')
            // Only HTTPS from the file: it can never downgrade the sync to plain HTTP.
            if (!url.startsWith("https://") || url == store.apiBaseUrl) return null
            store.apiBaseUrl = url
            Log.i(TAG, "API moved to $url")
            url
        } catch (e: Exception) {
            Log.w(TAG, "discovery failed: ${e.message}")
            null
        } finally {
            connection?.disconnect()
        }
    }

    /** One heartbeat to [base]. Null when the server could not be reached at all. */
    private fun heartbeatAt(context: Context, store: LockStore, protectionOn: Boolean, base: String, token: String): Result? {
        val body = JSONObject()
            .put("protectionOn", protectionOn)
            .put("usageAccess", hasUsageAccess(context))
            .put("shortcutOn", AppLockService.isShortcutOn(context))
            .put("appVersion", appVersion(context))
        val now = System.currentTimeMillis()
        val sendApps = now - store.lastAppsSentAt > APPS_EVERY_MS
        if (sendApps) {
            body.put(
                "installedApps",
                JSONArray(InstalledApps.list(context, withIcons = false).map {
                    JSONObject().put("package", it.packageName).put("label", it.label)
                }),
            )
        }

        var connection: HttpURLConnection? = null
        return try {
            connection = (URL("$base/v1/device/heartbeat").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 10_000
                readTimeout = 15_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("X-Device-Token", token)
            }
            connection.outputStream.use { it.write(body.toString().toByteArray()) }
            when (val code = connection.responseCode) {
                in 200..299 -> {
                    val json = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
                    store.saveState(json)
                    if (sendApps) store.lastAppsSentAt = now
                    Result.Updated(LockState.fromJson(json))
                }
                401 -> {
                    // Only a definite "this phone is unknown" ends enforcement, never a
                    // proxy or deploy hiccup that happens to answer 401.
                    val body = connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
                    val errorCode = runCatching { JSONObject(body).getJSONObject("error").getString("code") }.getOrNull()
                    if (errorCode == "DEVICE_UNAUTHORIZED") {
                        store.forget()
                        Result.Unregistered
                    } else {
                        Result.Failed
                    }
                }
                else -> {
                    Log.w(TAG, "heartbeat HTTP $code")
                    // Cloudflare answering for a tunnel whose computer is gone.
                    val viaCloudflare = connection.getHeaderField("Server")?.contains("cloudflare") == true
                    if (viaCloudflare && code in setOf(502, 503, 530)) null else Result.Failed
                }
            }
        } catch (e: IOException) {
            // No answer at all (unknown host, refused, timed out): the address may have changed.
            Log.w(TAG, "heartbeat unreachable: ${e.message}")
            null
        } catch (e: Exception) {
            // Offline: keep enforcing the last known state.
            Log.w(TAG, "heartbeat failed: ${e.message}")
            Result.Failed
        } finally {
            connection?.disconnect()
        }
    }

    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun appVersion(context: Context): String = try {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "unknown"
    } catch (_: Exception) {
        "unknown"
    }
}
