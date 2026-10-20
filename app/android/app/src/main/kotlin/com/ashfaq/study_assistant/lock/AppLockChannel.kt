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
import com.ashfaq.study_assistant.update.AutoUpdater
import com.ashfaq.study_assistant.widget.StudyWidget
import org.json.JSONObject
import java.util.concurrent.Executors

/** The Flutter side's handle on the native app blocker. */
class AppLockChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val store = LockStore(activity)
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(
                mapOf(
                    "protectionOn" to AppLockService.isEnabled(activity),
                    "usageAccess" to LockSync.hasUsageAccess(activity),
                    "shortcutOn" to AppLockService.isShortcutOn(activity),
                    "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                    "ownerUserId" to store.ownerUserId,
                    "deviceToken" to store.deviceToken,
                    "apiBaseUrl" to store.apiBaseUrl,
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

            "updateWidget" -> {
                @Suppress("UNCHECKED_CAST")
                StudyWidget.save(activity, call.arguments as? Map<String, Any?> ?: emptyMap())
                result.success(null)
            }

            "versionCode" -> {
                val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                result.success(if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong())
            }

            "canSelfUpdate" -> result.success(AutoUpdater.enabled(activity))

            "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull() ?: "")

            "installApk" -> {
                val path = call.argument<String>("path")
                if (!AutoUpdater.enabled(activity) || path == null) {
                    result.success(false)
                } else {
                    // Through PackageInstaller, so this app becomes the installer of
                    // record and later updates can install without asking.
                    executor.execute {
                        val ok = try {
                            AutoUpdater.install(activity, java.io.File(path))
                        } catch (_: Exception) {
                            false
                        }
                        main.post { result.success(ok) }
                    }
                }
            }

            "autoUpdate" -> {
                AutoUpdater.runAsync(activity) { started -> main.post { result.success(started) } }
            }

            "pinWidget" -> {
                result.success(StudyWidget.requestPin(activity))
            }

            "clearWidget" -> {
                StudyWidget.clear(activity)
                result.success(null)
            }

            "applyState" -> {
                val json = call.argument<String>("state")
                if (json != null) {
                    store.saveState(JSONObject(json))
                    AppLockService.instance?.onLockStateChanged()
                }
                result.success(null)
            }

            "syncNow" -> {
                AppLockService.instance?.syncNow()
                result.success(null)
            }

            "getInstalledApps" -> executor.execute {
                val withIcons = call.argument<Boolean>("withIcons") ?: true
                val apps = InstalledApps.list(activity, withIcons).map {
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

    private companion object {
        /** One background thread for the whole process (activities come and go). */
        val executor: java.util.concurrent.ExecutorService = Executors.newSingleThreadExecutor()
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
