package com.ashfaq.study_assistant.lock

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LockPolicyTest {
    private val launcher = "com.google.android.apps.nexuslauncher"
    private val allowed = setOf(launcher, "com.ashfaq.study_assistant", "com.google.android.inputmethod.latin")
    private val launchable = setOf(
        "com.google.android.youtube",
        "com.android.chrome",
        "com.android.settings",
        "com.android.vending",
        "com.google.android.gm",
    )

    private fun block(pkg: String, state: LockState, cls: String? = null) =
        LockPolicy.shouldBlock(pkg, cls, state, allowed, launchable)

    private val youtubeLock = LockState(locked = true, packages = setOf("com.google.android.youtube"))

    @Test
    fun `nothing is blocked while unlocked`() {
        assertFalse(block("com.google.android.youtube", LockState(locked = false, packages = setOf("com.google.android.youtube"))))
    }

    @Test
    fun `only the chosen apps are blocked`() {
        assertTrue(block("com.google.android.youtube", youtubeLock))
        assertFalse(block("com.google.android.gm", youtubeLock))
    }

    @Test
    fun `calls, emergency, launcher and keyboard are never blocked`() {
        val everything = LockState(locked = true, wholePhone = true, strict = true)
        for (pkg in listOf(
            "com.google.android.dialer",
            "com.samsung.android.incallui",
            "com.android.server.telecom",
            "com.google.android.apps.safetyhub",
            "com.android.systemui",
            launcher,
            "com.google.android.inputmethod.latin",
        )) {
            assertFalse(pkg, block(pkg, everything))
        }
    }

    @Test
    fun `emergency alerts, Wi-Fi sign-in and SIM toolkit are never blocked`() {
        val everything = LockState(locked = true, wholePhone = true, strict = true)
        for (pkg in listOf(
            "com.android.cellbroadcastreceiver",
            "com.google.android.cellbroadcastreceiver",
            "com.android.captiveportallogin",
            "com.google.android.captiveportallogin",
            "com.android.stk",
        )) {
            assertFalse(pkg, block(pkg, everything))
            assertTrue(pkg, LockPolicy.isNeverBlocked(pkg))
        }
    }

    @Test
    fun `whole phone blocks launchable apps only`() {
        val whole = LockState(locked = true, wholePhone = true)
        assertTrue(block("com.android.chrome", whole))
        assertTrue(block("com.android.vending", whole, "com.android.vending.AssetBrowserActivity"))
        // Background system screens without a launcher icon keep working.
        assertFalse(block("com.google.android.gms", whole))
    }

    @Test
    fun `strict mode blocks settings, stores and uninstallers`() {
        val strict = youtubeLock.copy(strict = true)
        assertTrue(block("com.android.settings", strict, "com.android.settings.homepage.SettingsHomepageActivity"))
        assertTrue(block("com.android.settings", strict, "com.android.settings.Settings\$AccessibilitySettingsActivity"))
        assertTrue(block("com.android.settings", strict, "com.android.settings.SubSettings"))
        assertTrue(block("com.android.vending", strict, "com.android.vending.AssetBrowserActivity"))
        assertTrue(block("com.google.android.packageinstaller", strict, "com.android.packageinstaller.UninstallerActivity"))
    }

    @Test
    fun `strict mode keeps the screens that get the phone online`() {
        val strict = youtubeLock.copy(strict = true)
        for (cls in listOf(
            "com.android.settings.Settings\$WifiSettingsActivity",
            "com.android.settings.Settings\$NetworkDashboardActivity",
            "com.android.settings.Settings\$MobileNetworkActivity",
            "com.android.settings.Settings\$DataUsageSummaryActivity",
            "com.android.settings.panel.SettingsPanelActivity",
        )) {
            assertFalse(cls, block("com.android.settings", strict, cls))
        }
    }

    @Test
    fun `an unknown settings screen is blocked in strict mode`() {
        assertTrue(block("com.android.settings", youtubeLock.copy(strict = true), null))
    }

    @Test
    fun `settings stay open without strict mode`() {
        assertFalse(block("com.android.settings", youtubeLock, "com.android.settings.homepage.SettingsHomepageActivity"))
    }

    @Test
    fun `locked apps can never be offered as never-blocked`() {
        assertFalse(LockPolicy.isNeverBlocked("com.google.android.youtube"))
        assertFalse(LockPolicy.isNeverBlocked("com.android.settings"))
    }
}
