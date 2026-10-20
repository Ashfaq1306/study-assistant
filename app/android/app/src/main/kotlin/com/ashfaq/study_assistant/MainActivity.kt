package com.ashfaq.study_assistant

import android.content.Intent
import com.ashfaq.study_assistant.lock.AppLockChannel
import com.ashfaq.study_assistant.lock.InstalledApps
import com.ashfaq.study_assistant.update.AutoUpdater
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(AppLockChannel(this))
        }
        // Test builds: keep the app up to date in the background, and check now.
        AutoUpdater.schedule(this)
        AutoUpdater.runAsync(this)
    }

    /** The blocker brought us to the front over a locked app: tell Flutter to show the lock screen. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val pkg = intent.getStringExtra(EXTRA_LOCKED_PACKAGE) ?: return
        channel?.invokeMethod("onLockedApp", mapOf("package" to pkg, "label" to InstalledApps.label(this, pkg)))
    }

    companion object {
        const val CHANNEL = "study_assistant/app_lock"
        const val EXTRA_LOCKED_PACKAGE = "locked_package"
    }
}
