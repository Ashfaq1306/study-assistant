package com.ashfaq.study_assistant.lock

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.telecom.TelecomManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import android.view.inputmethod.InputMethodManager
import com.ashfaq.study_assistant.MainActivity
import java.util.concurrent.Executors

/**
 * Enforces locks: whenever a blocked app is on screen, it sends the phone home
 * and brings Study Assistant's lock screen up instead.
 *
 * Two triggers: window changes (an app opening), and, while a lock is on, a
 * check of every visible app window every [ENFORCE_EVERY_MS] (catches split
 * screen and apps that were already open when the lock started). It reads
 * only which package owns each window, never window content.
 *
 * Also syncs with the server, so locks start and end with the app closed.
 * Accessibility services may start activities from the background, and
 * Android restarts an enabled service after a reboot.
 */
class AppLockService : AccessibilityService() {
    private lateinit var store: LockStore
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile private var alwaysAllowed: Set<String> = emptySet()
    @Volatile private var launchable: Set<String> = emptySet()
    @Volatile private var safetyApps: Set<String> = emptySet()
    @Volatile private var syncing = false

    private var lastBlockedPackage: String? = null
    private var lastBlockedAt = 0L

    /** The real app in front (system UI, keyboards and this app don't count). */
    private var foregroundPackage: String? = null

    /** Last real screen (activity) seen per package, so re-checks judge Settings by its screen. */
    private val lastScreen = HashMap<String, String>()

    private val syncLoop = object : Runnable {
        override fun run() {
            syncNow()
            handler.postDelayed(this, if (store.state().locked) SYNC_LOCKED_MS else SYNC_IDLE_MS)
        }
    }

    private val enforceLoop = object : Runnable {
        override fun run() {
            if (store.state().locked) {
                try {
                    // Nothing to see with the screen off: save the battery.
                    if ((getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive) enforceVisibleWindows()
                } catch (e: Throwable) {
                    Log.e(TAG, "enforcement check failed", e)
                }
                handler.postDelayed(this, ENFORCE_EVERY_MS)
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        store = LockStore(this)
        refreshPackageSets()
        instance = this
        handler.post(syncLoop)
        onLockStateChanged()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Any crash would unbind the service and end every lock: contain it.
        try {
            handleEvent(event)
        } catch (e: Throwable) {
            Log.e(TAG, "event handling failed", e)
        }
    }

    private fun handleEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName || pkg == SYSTEM_UI || pkg in alwaysAllowed) {
            // Ours, the notification shade or a keyboard: not an app the student switched to.
            if (pkg == packageName) foregroundPackage = pkg
            return
        }
        foregroundPackage = pkg

        val cls = event.className?.toString()
        // In Settings & co. only real screens decide (Wi-Fi stays reachable); their
        // splash and view windows say nothing about which screen is opening.
        if (LockPolicy.isStrictBlocked(pkg)) {
            if (cls == null || !isActivity(pkg, cls)) return
            lastScreen[pkg] = cls
        }

        if (shouldBlock(pkg, cls)) block(pkg)
        if (System.currentTimeMillis() - store.lastSyncAt > SYNC_LOCKED_MS) syncNow()
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        executor.shutdown()
        if (instance === this) instance = null
        super.onDestroy()
    }

    /** Called when a new lock state was stored: start or stop enforcing right away. */
    fun onLockStateChanged() {
        handler.post {
            handler.removeCallbacks(enforceLoop)
            if (store.state().locked) handler.post(enforceLoop)
        }
    }

    /** Asks the server for the latest lock state, without blocking the UI thread. */
    fun syncNow() {
        if (syncing) return
        syncing = true
        executor.execute {
            try {
                val wasLocked = store.state().locked
                val result = LockSync.heartbeat(this, store, protectionOn = true)
                refreshPackageSets()
                if (result !is LockSync.Result.Failed && store.state().locked != wasLocked) onLockStateChanged()
            } catch (e: Throwable) {
                // A crash here would unbind the service and switch every lock off. Never let it.
                Log.e(TAG, "sync failed", e)
            } finally {
                syncing = false
            }
        }
    }

    private fun shouldBlock(pkg: String, cls: String?): Boolean {
        // Settings & co. are judged by their screen; without one known yet, wait for it.
        val screen = cls ?: lastScreen[pkg]
        if (LockPolicy.isStrictBlocked(pkg) && screen == null) return false
        return LockPolicy.shouldBlock(pkg, screen, store.state(), alwaysAllowed, launchable)
    }

    /** Blocks a locked app in any visible app window: full screen, split screen or floating. */
    private fun enforceVisibleWindows() {
        val visible = try {
            windows
        } catch (e: Exception) {
            Log.w(TAG, "window list unavailable", e)
            return
        }
        val appWindows = visible.mapNotNull { window ->
            if (window.type != AccessibilityWindowInfo.TYPE_APPLICATION) return@mapNotNull null
            val pkg = try {
                window.root?.packageName?.toString()
            } catch (_: Exception) {
                null
            } ?: return@mapNotNull null
            LockPolicy.VisibleWindow(pkg, active = window.isActive || window.isFocused, pictureInPicture = window.isInPictureInPictureMode)
        }
        val pkg = LockPolicy.windowToBlock(
            appWindows,
            store.state(),
            alwaysAllowed,
            launchable,
            packageName,
            safetyApps,
            lastScreen,
        ) ?: return
        // A window that keeps coming back after going home (pop-up/freeform): don't
        // press home in a tight loop; give it a pause between attempts.
        if (pkg == lastBlockedPackage && System.currentTimeMillis() - lastBlockedAt < LOOP_BACKOFF_MS) return
        block(pkg)
    }

    private fun block(pkg: String) {
        val now = System.currentTimeMillis()
        if (pkg == lastBlockedPackage && now - lastBlockedAt < DEBOUNCE_MS) {
            // Some apps open a second window while starting (Chrome's first-run
            // screen, splash trampolines). Check again shortly instead of ignoring it.
            handler.postDelayed({
                if (foregroundPackage == pkg && shouldBlock(pkg, null)) {
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

    private fun refreshPackageSets() {
        alwaysAllowed = computeAlwaysAllowed()
        safetyApps = setOfNotNull((getSystemService(Context.TELECOM_SERVICE) as? TelecomManager)?.defaultDialerPackage)
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        launchable = packageManager.queryIntentActivities(launcher, 0).map { it.activityInfo.packageName }.toSet()
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
        private const val TAG = "AppLockService"
        private const val SYSTEM_UI = "com.android.systemui"
        private const val SYNC_LOCKED_MS = 60_000L
        private const val SYNC_IDLE_MS = 2 * 60_000L
        private const val ENFORCE_EVERY_MS = 1_500L
        private const val DEBOUNCE_MS = 800L
        private const val AFTER_HOME_MS = 350L
        private const val LOOP_BACKOFF_MS = 6_000L

        /** Settings keys holding the accessibility shortcut targets (volume keys, button, quick settings). */
        private val SHORTCUT_KEYS = listOf(
            "accessibility_shortcut_target_service",
            "accessibility_button_targets",
            "accessibility_qs_targets",
            "accessibility_key_gesture_targets",
        )

        @Volatile
        var instance: AppLockService? = null
            private set

        /** True when the user has switched the service on in Accessibility settings. */
        fun isEnabled(context: Context): Boolean = mentionsMe(
            context,
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES),
        )

        /**
         * True when an accessibility shortcut (holding both volume keys, the
         * accessibility button or a quick-settings tile) can switch the lock off
         * without opening Settings. The app asks the student to turn it off.
         */
        fun isShortcutOn(context: Context): Boolean = SHORTCUT_KEYS.any { key ->
            // Some keys are unreadable for normal apps on newer Android: skip those.
            val value = try {
                Settings.Secure.getString(context.contentResolver, key)
            } catch (_: SecurityException) {
                null
            }
            mentionsMe(context, value)
        }

        private fun mentionsMe(context: Context, value: String?): Boolean {
            if (value.isNullOrBlank()) return false
            val me = ComponentName(context, AppLockService::class.java)
            return value.split(':').any { ComponentName.unflattenFromString(it.trim()) == me }
        }
    }
}
