package com.ashfaq.study_assistant.lock

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.telecom.TelecomManager
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager
import com.ashfaq.study_assistant.MainActivity
import java.util.concurrent.Executors

/**
 * Enforces locks: whenever a blocked app comes to the front, it brings Study
 * Assistant's lock screen on top instead. Also syncs with the server every
 * minute, so locks start and end even while the app itself is closed.
 *
 * Accessibility services are allowed to start activities from the background,
 * and Android restarts an enabled service after a reboot.
 */
class AppLockService : AccessibilityService() {
    private lateinit var store: LockStore
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private var alwaysAllowed: Set<String> = emptySet()
    private var lastBlockedPackage: String? = null
    /** The app currently in front, from the latest window change. */
    private var foregroundPackage: String? = null
    private var lastBlockedAt = 0L
    private var syncing = false

    private val syncLoop = object : Runnable {
        override fun run() {
            syncNow()
            handler.postDelayed(this, SYNC_EVERY_MS)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        store = LockStore(this)
        alwaysAllowed = computeAlwaysAllowed()
        instance = this
        handler.post(syncLoop)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        foregroundPackage = pkg
        if (pkg == packageName) return

        val cls = event.className?.toString()
        // In Settings & co. only real screens decide (Wi-Fi stays reachable); their
        // splash and view windows say nothing about which screen is opening.
        if (LockPolicy.isStrictBlocked(pkg) && !isActivity(pkg, cls)) return

        if (LockPolicy.shouldBlock(pkg, cls, store.state(), alwaysAllowed)) {
            block(pkg)
        }
        if (System.currentTimeMillis() - store.lastSyncAt > SYNC_EVERY_MS) syncNow()
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        handler.removeCallbacks(syncLoop)
        executor.shutdown()
        if (instance === this) instance = null
        super.onDestroy()
    }

    /** Asks the server for the latest lock state, without blocking the UI thread. */
    fun syncNow() {
        if (syncing) return
        syncing = true
        executor.execute {
            try {
                LockSync.heartbeat(this, store, protectionOn = true)
                alwaysAllowed = computeAlwaysAllowed()
            } finally {
                syncing = false
            }
        }
    }

    private fun block(pkg: String) {
        val now = System.currentTimeMillis()
        if (pkg == lastBlockedPackage && now - lastBlockedAt < DEBOUNCE_MS) {
            // Some apps open a second window while starting (Chrome's first-run
            // screen, splash trampolines). Check again shortly instead of ignoring it.
            handler.postDelayed({
                if (foregroundPackage == pkg &&
                    LockPolicy.shouldBlock(pkg, null, store.state(), alwaysAllowed)
                ) {
                    lastBlockedAt = 0
                    block(pkg)
                }
            }, DEBOUNCE_MS)
            return
        }
        lastBlockedPackage = pkg
        lastBlockedAt = now
        store.pendingLockedPackage = pkg
        // Leave the locked app first, so it cannot open more windows over the lock screen.
        performGlobalAction(GLOBAL_ACTION_HOME)
        // The home transition finishes asynchronously; show the lock screen after it.
        handler.postDelayed({
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP,
                    )
                    .putExtra(MainActivity.EXTRA_LOCKED_PACKAGE, pkg),
            )
        }, AFTER_HOME_MS)
    }

    private val activityCache = HashMap<String, Boolean>()

    private fun isActivity(pkg: String, cls: String?): Boolean {
        if (cls == null) return false
        return activityCache.getOrPut("$pkg/$cls") {
            try {
                packageManager.getActivityInfo(ComponentName(pkg, cls), 0)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    /** This phone's launcher(s), dialer and keyboards: never blocked. */
    private fun computeAlwaysAllowed(): Set<String> {
        val allowed = mutableSetOf(packageName)
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        // Settings registers a fallback home screen too; it must stay blockable in strict mode.
        packageManager.queryIntentActivities(home, 0)
            .map { it.activityInfo.packageName }
            .filterNot(LockPolicy::isStrictBlocked)
            .forEach { allowed += it }
        (getSystemService(Context.TELECOM_SERVICE) as? TelecomManager)?.defaultDialerPackage?.let { allowed += it }
        (getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
            ?.enabledInputMethodList
            ?.forEach { allowed += it.packageName }
        return allowed
    }

    companion object {
        private const val SYNC_EVERY_MS = 60_000L
        private const val DEBOUNCE_MS = 800L
        private const val AFTER_HOME_MS = 350L

        @Volatile
        var instance: AppLockService? = null
            private set

        /** True when the user has switched the service on in Accessibility settings. */
        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val me = ComponentName(context, AppLockService::class.java)
            return enabled.split(':').any { ComponentName.unflattenFromString(it) == me }
        }
    }
}
