package com.ashfaq.study_assistant.lock

/**
 * Decides whether an app on screen must be blocked.
 *
 * Safety first: calls, emergency alerts, Wi-Fi sign-in pages, the SIM toolkit,
 * the keyboard, the launcher and the system UI are never blocked. Strict mode
 * also blocks Settings, app stores and uninstallers while a lock is on, so the
 * lock cannot simply be switched off; Wi-Fi and mobile-data screens stay
 * reachable so the student can always get online to take the exam.
 */
object LockPolicy {
    private val ALWAYS_ALLOWED = setOf(
        "android",
        "com.android.systemui",
        "com.android.phone",
        "com.android.server.telecom",
        "com.android.dialer",
        "com.google.android.dialer",
        "com.samsung.android.dialer",
        "com.android.incallui",
        "com.samsung.android.incallui",
        "com.android.emergency",
        "com.google.android.apps.safetyhub",
        "com.samsung.android.emergency",
        "com.android.stk",
        "com.samsung.android.stk",
    )

    /** Fragments that mark calling, emergency-alert and Wi-Fi sign-in apps from any maker. */
    private val ALLOWED_HINTS = listOf("dialer", "incallui", "telecom", "emergency", "cellbroadcast", "captiveportal")

    private val STRICT_BLOCKED = setOf(
        "com.android.settings",
        "com.android.vending",
        "com.google.android.packageinstaller",
        "com.android.packageinstaller",
        "com.samsung.android.packageinstaller",
        "com.google.android.permissioncontroller",
        "com.android.permissioncontroller",
        "com.sec.android.app.samsungapps",
        "com.miui.securitycenter",
        "com.coloros.safecenter",
    )

    /** Settings screens that only help the student get online. */
    private val CONNECTIVITY_HINTS = listOf("wifi", "network", "internet", "mobile", "sim", "airplane", "datausage", "panel")

    /** Settings, stores and uninstallers: blocked in strict mode. */
    fun isStrictBlocked(packageName: String): Boolean = packageName in STRICT_BLOCKED

    /** Calls, emergency and sign-in apps: never blocked, so not offered in the app picker either. */
    fun isNeverBlocked(packageName: String): Boolean =
        packageName in ALWAYS_ALLOWED || ALLOWED_HINTS.any { packageName.contains(it, ignoreCase = true) }

    /** What the re-check needs to know about one visible app window. */
    data class VisibleWindow(val packageName: String, val active: Boolean, val pictureInPicture: Boolean)

    /**
     * Which visible window (if any) the periodic re-check should block.
     *
     * Pauses only while a safety app (a call, the dialer, an emergency screen)
     * is the active window, so an emergency call is never interrupted; this
     * app, launchers and keyboards do not pause it, or split screen next to
     * them would be a way around the lock. Picture-in-picture windows are
     * ignored (going home cannot clear them). Settings & co. are judged by the
     * last real screen seen in them; unknown screens are left alone.
     *
     * @param safetyApps the phone's default dialer (calls/emergency are added here).
     * @param lastScreen last activity class seen per package.
     */
    fun windowToBlock(
        windows: List<VisibleWindow>,
        state: LockState,
        alwaysAllowed: Set<String>,
        launchable: Set<String>,
        ownPackage: String,
        safetyApps: Set<String>,
        lastScreen: Map<String, String>,
    ): String? {
        if (!state.locked) return null
        val active = windows.firstOrNull { it.active }?.packageName
        if (active != null && (active in safetyApps || isNeverBlocked(active))) return null
        return windows.firstOrNull { window ->
            if (window.pictureInPicture || window.packageName == ownPackage) return@firstOrNull false
            val screen = lastScreen[window.packageName]
            if (isStrictBlocked(window.packageName) && screen == null) return@firstOrNull false
            shouldBlock(window.packageName, screen, state, alwaysAllowed, launchable)
        }?.packageName
    }

    /**
     * @param alwaysAllowed this phone's launcher, dialer and keyboards.
     * @param launchable apps with a launcher icon; "whole phone" only blocks
     *   these, so background system screens (alerts, sign-in pages) keep working.
     */
    fun shouldBlock(
        packageName: String,
        className: String?,
        state: LockState,
        alwaysAllowed: Set<String>,
        launchable: Set<String>,
    ): Boolean {
        if (!state.locked) return false
        if (packageName in alwaysAllowed || isNeverBlocked(packageName)) return false

        val chosen = packageName in state.packages || (state.wholePhone && packageName in launchable)
        if (packageName in STRICT_BLOCKED) {
            if (!state.strict && !chosen) return false
            // Even when locked, the screens that get the phone online stay open.
            val screen = className?.lowercase() ?: return true
            return CONNECTIVITY_HINTS.none { screen.contains(it) }
        }
        return chosen
    }
}
