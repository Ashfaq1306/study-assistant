package com.ashfaq.study_assistant.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import com.ashfaq.study_assistant.MainActivity
import com.ashfaq.study_assistant.R

/**
 * The home-screen widget. The app pushes a small snapshot (today's minutes,
 * streak, running session); the widget draws it without waking the app. A
 * running session counts down in a Chronometer, so no updates are needed
 * while it ticks.
 */
object StudyWidget {
    private const val PREFS = "study_widget"

    /** Saves what the app last knew and redraws every widget. */
    fun save(context: Context, data: Map<String, Any?>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("mode", data["mode"] as? String ?: "idle")
            .putString("title", data["title"] as? String ?: "")
            .putString("subtitle", data["subtitle"] as? String ?: "")
            .putLong("endsAt", (data["endsAt"] as? Number)?.toLong() ?: 0L)
            .putInt("todayMinutes", (data["todayMinutes"] as? Number)?.toInt() ?: 0)
            .putInt("streakDays", (data["streakDays"] as? Number)?.toInt() ?: 0)
            .apply()
        refresh(context)
    }

    /** Forgets the snapshot (sign out). */
    fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
        refresh(context)
    }

    /** Asks the launcher to add the widget (it shows its own confirmation). False if unsupported. */
    fun requestPin(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        if (!manager.isRequestPinAppWidgetSupported) return false
        return manager.requestPinAppWidget(ComponentName(context, StudyWidgetProvider::class.java), null, null)
    }

    fun refresh(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, StudyWidgetProvider::class.java))
        if (ids.isEmpty()) return
        val views = build(context)
        ids.forEach { manager.updateAppWidget(it, views) }
    }

    private fun build(context: Context): RemoteViews {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val endsAt = prefs.getLong("endsAt", 0L)
        var mode = prefs.getString("mode", "idle") ?: "idle"
        // The timer ran out since the app last spoke: it's exam time.
        if (mode == "studying" && endsAt in 1..now) mode = "exam"

        val views = RemoteViews(context.packageName, R.layout.study_widget)
        val today = prefs.getInt("todayMinutes", 0)
        views.setTextViewText(R.id.widget_today, if (today >= 60) "${today / 60}h ${today % 60}m" else "${today}m")
        views.setTextViewText(R.id.widget_streak, "${prefs.getInt("streakDays", 0)}")

        val title = prefs.getString("title", "").orEmpty()
        when (mode) {
            "studying" -> {
                views.setTextViewText(R.id.widget_title, title.ifEmpty { "Studying" })
                views.setViewVisibility(R.id.widget_timer, View.VISIBLE)
                views.setChronometer(R.id.widget_timer, SystemClock.elapsedRealtime() + (endsAt - now), null, true)
                views.setChronometerCountDown(R.id.widget_timer, true)
                views.setTextViewText(R.id.widget_subtitle, "left to focus")
                badge(views, "Focus")
                views.setTextViewText(R.id.widget_action, "Open timer")
                scheduleRefresh(context, endsAt)
            }
            "exam" -> {
                views.setTextViewText(R.id.widget_title, title.ifEmpty { "Exam time" })
                views.setViewVisibility(R.id.widget_timer, View.GONE)
                views.setTextViewText(R.id.widget_subtitle, "Pass your exam to unlock your apps")
                badge(views, "Exam")
                views.setTextViewText(R.id.widget_action, "Take exam")
            }
            "locked" -> {
                views.setTextViewText(R.id.widget_title, title.ifEmpty { "Locked by your parent" })
                views.setViewVisibility(R.id.widget_timer, View.GONE)
                views.setTextViewText(R.id.widget_subtitle, prefs.getString("subtitle", "").orEmpty())
                badge(views, "Locked")
                views.setTextViewText(R.id.widget_action, "Take exam")
            }
            "signedOut" -> {
                views.setTextViewText(R.id.widget_title, "Welcome!")
                views.setViewVisibility(R.id.widget_timer, View.GONE)
                views.setTextViewText(R.id.widget_subtitle, "Sign in to start studying")
                badge(views, null)
                views.setTextViewText(R.id.widget_action, "Open app")
            }
            else -> {
                views.setTextViewText(R.id.widget_title, "Ready to study?")
                views.setViewVisibility(R.id.widget_timer, View.GONE)
                views.setTextViewText(
                    R.id.widget_subtitle,
                    prefs.getString("subtitle", "").orEmpty().ifEmpty { "Pick a subject and lock distractions" },
                )
                badge(views, null)
                views.setTextViewText(R.id.widget_action, "Start")
            }
        }

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, open)
        views.setOnClickPendingIntent(R.id.widget_action, open)
        return views
    }

    private fun badge(views: RemoteViews, text: String?) {
        views.setViewVisibility(R.id.widget_badge, if (text == null) View.GONE else View.VISIBLE)
        if (text != null) views.setTextViewText(R.id.widget_badge, text)
    }

    /** Flip to "exam time" when the timer ends (inexact: no special permission needed). */
    private fun scheduleRefresh(context: Context, at: Long) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = PendingIntent.getBroadcast(
            context,
            1,
            Intent(context, StudyWidgetProvider::class.java).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarms.setWindow(AlarmManager.RTC, at, 60_000L, intent)
    }
}

class StudyWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        StudyWidget.refresh(context)
    }
}
