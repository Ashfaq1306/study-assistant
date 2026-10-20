package com.ashfaq.study_assistant.lock

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** What the phone must block, as last reported by the server. */
data class LockState(
    val locked: Boolean = false,
    val wholePhone: Boolean = false,
    val packages: Set<String> = emptySet(),
    val strict: Boolean = false,
    val title: String? = null,
) {
    companion object {
        fun fromJson(json: JSONObject): LockState {
            val packages = json.optJSONArray("packages") ?: JSONArray()
            val reasons = json.optJSONArray("reasons") ?: JSONArray()
            return LockState(
                locked = json.optBoolean("locked", false),
                wholePhone = json.optBoolean("wholePhone", false),
                packages = (0 until packages.length()).map { packages.getString(it) }.toSet(),
                strict = json.optBoolean("strict", false),
                title = if (reasons.length() > 0) reasons.getJSONObject(0).optString("title") else null,
            )
        }
    }
}

/**
 * Lock settings that must survive the app being closed, killed or signed out:
 * the API address, this phone's device token and the last known lock state.
 * Offline, the last state keeps applying (staying locked is the safe default).
 */
class LockStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    var apiBaseUrl: String?
        get() = prefs.getString(KEY_BASE_URL, null)
        set(value) = prefs.edit().putString(KEY_BASE_URL, value).apply()

    var deviceToken: String?
        get() = prefs.getString(KEY_TOKEN, null)
        set(value) = prefs.edit().putString(KEY_TOKEN, value).apply()

    /** The student this device token belongs to. */
    var ownerUserId: String?
        get() = prefs.getString(KEY_OWNER, null)
        set(value) = prefs.edit().putString(KEY_OWNER, value).apply()

    var lastSyncAt: Long
        get() = prefs.getLong(KEY_LAST_SYNC, 0)
        set(value) = prefs.edit().putLong(KEY_LAST_SYNC, value).apply()

    var lastAppsSentAt: Long
        get() = prefs.getLong(KEY_APPS_SENT, 0)
        set(value) = prefs.edit().putLong(KEY_APPS_SENT, value).apply()

    /** A blocked app the user tried to open before the app UI was running. */
    var pendingLockedPackage: String?
        get() = prefs.getString(KEY_PENDING, null)
        set(value) = prefs.edit().putString(KEY_PENDING, value).apply()

    fun state(): LockState {
        val raw = prefs.getString(KEY_STATE, null) ?: return LockState()
        return try {
            LockState.fromJson(JSONObject(raw))
        } catch (_: Exception) {
            LockState()
        }
    }

    fun saveState(json: JSONObject) {
        prefs.edit().putString(KEY_STATE, json.toString()).putLong(KEY_LAST_SYNC, System.currentTimeMillis()).apply()
    }

    /** The device is no longer registered (account removed or disabled): nothing to enforce. */
    fun forget() {
        prefs.edit().remove(KEY_TOKEN).remove(KEY_OWNER).remove(KEY_STATE).remove(KEY_PENDING).apply()
    }

    private companion object {
        const val NAME = "study_assistant_lock"
        const val KEY_BASE_URL = "api_base_url"
        const val KEY_TOKEN = "device_token"
        const val KEY_OWNER = "owner_user_id"
        const val KEY_STATE = "lock_state"
        const val KEY_LAST_SYNC = "last_sync_at"
        const val KEY_APPS_SENT = "apps_sent_at"
        const val KEY_PENDING = "pending_locked_package"
    }
}
