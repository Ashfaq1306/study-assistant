package com.ashfaq.study_assistant.lock

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.Executors

/** The Flutter side's handle on the native app blocker. */
class AppLockChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val store = LockStore(activity)
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(
                mapOf(
                    "protectionOn" to AppLockService.isEnabled(activity),
                    "usageAccess" to LockSync.hasUsageAccess(activity),
                    "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                    "ownerUserId" to store.ownerUserId,
                    "deviceToken" to store.deviceToken,
                    "locked" to store.state().locked,
                ),
            )

            "configure" -> {
                store.apiBaseUrl = call.argument<String>("baseUrl")
                store.deviceToken = call.argument<String>("deviceToken")
                store.ownerUserId = call.argument<String>("userId")
                store.lastAppsSentAt = 0
                AppLockService.instance?.syncNow()
                result.success(null)
            }

            "applyState" -> {
                val json = call.argument<String>("state")
                if (json != null) store.saveState(JSONObject(json))
                result.success(null)
            }

            "syncNow" -> {
                AppLockService.instance?.syncNow()
                result.success(null)
            }

            "getInstalledApps" -> executor.execute {
                val apps = InstalledApps.list(activity, withIcons = true).map {
                    mapOf("package" to it.packageName, "label" to it.label, "icon" to it.icon)
                }
                main.post { result.success(apps) }
            }

            "appLabel" -> result.success(InstalledApps.label(activity, call.argument<String>("package") ?: ""))

            "takePendingLockedPackage" -> {
                val pkg = store.pendingLockedPackage
                store.pendingLockedPackage = null
                result.success(pkg)
            }

            "openAccessibilitySettings" -> open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS), result)
            "openUsageAccessSettings" -> open(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS), result)
            "openAppDetails" -> open(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")),
                result,
            )
            "openBatterySettings" -> open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS), result)

            "goHome" -> {
                activity.startActivity(
                    Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun open(intent: Intent, result: MethodChannel.Result) {
        try {
            activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }
}
