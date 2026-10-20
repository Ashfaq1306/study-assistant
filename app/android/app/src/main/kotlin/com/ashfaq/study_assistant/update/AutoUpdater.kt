package com.ashfaq.study_assistant.update

import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log
import org.json.JSONArray
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Test builds keep themselves up to date from GitHub Releases. A background job
 * checks every few hours; a newer build for this phone's chip is downloaded and
 * installed through Android's PackageInstaller. When this app is its own
 * installer of record and the running build holds UPDATE_PACKAGES_WITHOUT_USER_ACTION,
 * Android 12+ lets the update go through without asking; otherwise Android shows
 * its own confirmation the next time the app is open.
 *
 * Play Store builds never self-update: only test builds declare the install
 * permission, so [enabled] is false there.
 */
object AutoUpdater {
    private const val TAG = "AutoUpdater"
    private const val REPO = "Ashfaq1306/study-assistant"
    private const val JOB_ID = 4711
    private val executor = Executors.newSingleThreadExecutor()
    private val ABI_APK = Regex("-(arm64-v8a|armeabi-v7a|x86_64)\\.apk$")

    data class Update(val build: Int, val version: String, val url: String, val name: String)

    /**
     * Only test builds declare the install permission. (It is an app-op
     * permission, so Android never reports it as "granted"; whether installs are
     * allowed is the user's "install unknown apps" switch.)
     */
    fun enabled(context: Context): Boolean {
        val info = context.packageManager.getPackageInfo(
            context.packageName,
            android.content.pm.PackageManager.GET_PERMISSIONS,
        )
        return info.requestedPermissions?.contains(android.Manifest.permission.REQUEST_INSTALL_PACKAGES) == true
    }

    /** The pubspec build number (split APKs add the chip as thousands). */
    fun currentBuild(context: Context): Int {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
        return (code % 1000).toInt()
    }

    /** Schedules the periodic background check (idempotent). */
    fun schedule(context: Context) {
        if (!enabled(context)) return
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
        if (scheduler.getPendingJob(JOB_ID) != null) return
        scheduler.schedule(
            JobInfo.Builder(JOB_ID, ComponentName(context, UpdateJobService::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(TimeUnit.HOURS.toMillis(3), TimeUnit.HOURS.toMillis(1))
                .setPersisted(true)
                .build(),
        )
    }

    /** Checks, downloads and installs on a background thread. [done] gets true if an install started. */
    fun runAsync(context: Context, done: (Boolean) -> Unit = {}) {
        val app = context.applicationContext
        executor.execute {
            val started = try {
                val update = findUpdate(app)
                if (update == null) false else install(app, download(app, update))
            } catch (e: Exception) {
                Log.w(TAG, "update check failed", e)
                false
            }
            done(started)
        }
    }

    fun findUpdate(context: Context): Update? {
        if (!enabled(context)) return null
        val current = currentBuild(context)
        val abi = Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
        val releases = JSONArray(get("https://api.github.com/repos/$REPO/releases?per_page=10"))
        var best: Update? = null
        for (i in 0 until releases.length()) {
            val r = releases.getJSONObject(i)
            if (r.optBoolean("draft")) continue
            val tag = Regex("^v?(\\d+\\.\\d+\\.\\d+)-b(\\d+)$").find(r.optString("tag_name")) ?: continue
            val build = tag.groupValues[2].toInt()
            if (build <= current || (best != null && build <= best.build)) continue
            val assets = r.optJSONArray("assets") ?: continue
            var exact: Update? = null
            var universal: Update? = null
            for (j in 0 until assets.length()) {
                val a = assets.getJSONObject(j)
                val name = a.optString("name")
                if (!name.endsWith(".apk")) continue
                val candidate = Update(build, tag.groupValues[1], a.optString("browser_download_url"), name)
                if (abi.isNotEmpty() && name.endsWith("-$abi.apk")) exact = candidate
                else if (!ABI_APK.containsMatchIn(name)) universal = candidate
            }
            best = exact ?: universal ?: best
        }
        return best
    }

    private fun download(context: Context, update: Update): File {
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        val file = File(dir, update.name)
        if (file.exists() && file.length() > 0) return file
        val part = File(dir, "${update.name}.part")
        open(update.url).inputStream.use { input -> part.outputStream().use { input.copyTo(it) } }
        if (!part.renameTo(file)) throw IllegalStateException("could not save the update")
        // Old downloads are no longer needed.
        dir.listFiles()?.filter { it != file }?.forEach { it.delete() }
        return file
    }

    /** Hands the APK to Android's installer. Returns true when the session was committed. */
    fun install(context: Context, apk: File): Boolean {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("app.apk", 0, apk.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val status = PendingIntent.getBroadcast(
                context,
                id,
                Intent(context, UpdateStatusReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            session.commit(status.intentSender)
        }
        return true
    }

    private fun get(url: String): String = open(url).inputStream.bufferedReader().use { it.readText() }

    private fun open(url: String): HttpURLConnection {
        var target = URL(url)
        repeat(5) {
            val conn = target.openConnection() as HttpURLConnection
            conn.connectTimeout = 15_000
            conn.readTimeout = 60_000
            conn.setRequestProperty("User-Agent", "StudyAssistant-Updater")
            conn.setRequestProperty("Accept", "application/vnd.github+json, application/octet-stream")
            conn.instanceFollowRedirects = false
            val code = conn.responseCode
            if (code in 300..399) {
                target = URL(target, conn.getHeaderField("Location"))
                conn.disconnect()
            } else if (code in 200..299) {
                return conn
            } else {
                conn.disconnect()
                throw IllegalStateException("HTTP $code for $target")
            }
        }
        throw IllegalStateException("too many redirects")
    }
}

/** Android reports the install result here; it asks the user only when it must. */
class UpdateStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // Android wants a confirmation (e.g. the first update after a manual install).
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                try {
                    context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (e: Exception) {
                    Log.i("AutoUpdater", "confirmation must wait until the app is open", e)
                }
            }
            PackageInstaller.STATUS_SUCCESS -> Log.i("AutoUpdater", "updated")
            else -> Log.w("AutoUpdater", "update failed: ${intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)}")
        }
    }
}

/** The periodic background check. */
class UpdateJobService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        AutoUpdater.runAsync(this) { jobFinished(params, false) }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true
}
