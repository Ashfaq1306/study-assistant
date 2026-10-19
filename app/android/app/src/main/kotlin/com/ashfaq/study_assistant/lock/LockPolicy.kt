package com.ashfaq.study_assistant.lock

/**
 * Decides whether a window that just came to the front must be blocked.
 *
 * Safety first: calls, emergency, the keyboard, the launcher and the system UI
 * are never blocked. Strict mode also blocks Settings, app stores and
 * uninstallers while a lock is on, so the lock cannot simply be switched off,
 * but Wi-Fi and mobile-data screens stay reachable so the student can get
 * online to take the exam.
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
    )

    /** Fragments that mark calling/emergency apps from other makers. */
    private val ALLOWED_HINTS = listOf("dialer", "incallui", "telecom", "emergency")

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
    private val CONNECTIVITY_HINTS = listOf("wifi", "network", "internet", "mobile", "sim", "airplane", "data", "panel")

    /** Settings, stores and uninstallers: blocked in strict mode. */
    fun isStrictBlocked(packageName: String): Boolean = packageName in STRICT_BLOCKED

    /** Calls and emergency apps: never blocked, so not offered in the app picker either. */
    fun isNeverBlocked(packageName: String): Boolean =
        packageName in ALWAYS_ALLOWED || ALLOWED_HINTS.any { packageName.contains(it, ignoreCase = true) }

    fun shouldBlock(packageName: String, className: String?, state: LockState, alwaysAllowed: Set<String>): Boolean {
        if (!state.locked) return false
        if (packageName in alwaysAllowed || isNeverBlocked(packageName)) return false

        if (packageName in STRICT_BLOCKED) {
            if (!state.strict) return packageName in state.packages
            val screen = className?.lowercase() ?: return true
            return CONNECTIVITY_HINTS.none { screen.contains(it) }
        }
        return state.wholePhone || packageName in state.packages
    }
}
