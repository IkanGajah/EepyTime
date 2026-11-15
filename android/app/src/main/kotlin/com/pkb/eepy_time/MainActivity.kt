package com.pkb.eepy_time

import android.Manifest
import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.roundToInt

class MyDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Toast.makeText(
            context,
            "EepyTime: Izin Kunci Layar (Device Admin) diaktifkan",
            Toast.LENGTH_SHORT
        ).show()
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Toast.makeText(
            context,
            "EepyTime: Izin Kunci Layar (Device Admin) dinonaktifkan",
            Toast.LENGTH_SHORT
        ).show()
    }
}

object NativeTimerManager {
    const val CHANNEL_NAME = "eepy_time/native_control"
    const val NOTIFICATION_CHANNEL_ID = "eepy_time_countdown_channel"
    const val NOTIFICATION_ID = 1001
    private const val PREFS_NAME = "eepy_time_native_prefs"

    const val DEFAULT_FADE_WINDOW_MS = 20_000L
    private const val FADE_TICK_INTERVAL_MS = 250L

    private const val KEY_LAST_VOLUME = "last_volume_level"
    private const val KEY_MUTED_BY_APP = "muted_by_app"
    private const val KEY_IS_FADING = "is_fading"
    private const val KEY_FADE_START_VOLUME = "fade_start_volume"
    private const val KEY_FADE_WINDOW_MS = "fade_window_ms"
    private const val KEY_TIMER_STATUS = "timer_status" // "idle" | "running" | "paused" | "sleeping"
    private const val KEY_DEADLINE_MS = "deadline_ms"
    private const val KEY_INITIAL_SECONDS = "initial_seconds"
    private const val KEY_PAUSED_REMAINING_SECONDS = "paused_remaining_seconds"
    private const val KEY_PRESET_LABEL = "preset_label"
    private const val KEY_TOAST_ENABLED = "toast_enabled"
    private const val KEY_PENDING_COMPLETIONS = "pending_completions"

    // Data sesi tidur aktif (dihitung sejak timer habis / layar terkunci hingga layar dibuka kembali)
    private const val KEY_SLEEP_SESSION_KEY = "sleep_session_key"
    private const val KEY_SLEEP_START_MS = "sleep_start_ms"
    private const val KEY_SLEEP_START_ISO = "sleep_start_iso"
    private const val KEY_SLEEP_PRESET_LABEL = "sleep_preset_label"
    private const val KEY_SLEEP_TIMER_SECONDS = "sleep_timer_seconds"
    private const val KEY_SLEEP_LOCKED = "sleep_locked"
    private const val KEY_SLEEP_MUTED = "sleep_muted"

    const val ACTION_STOP = "com.pkb.eepy_time.ACTION_STOP"
    const val ACTION_SLEEP_NOW = "com.pkb.eepy_time.ACTION_SLEEP_NOW"
    const val ACTION_EXTEND_10M = "com.pkb.eepy_time.ACTION_EXTEND_10M"
    const val ACTION_FINISH_SLEEP = "com.pkb.eepy_time.ACTION_FINISH_SLEEP"
    const val ACTION_FADE_START_ALARM = "com.pkb.eepy_time.ACTION_FADE_START_ALARM"
    const val ACTION_DEADLINE_ALARM = "com.pkb.eepy_time.ACTION_DEADLINE_ALARM"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var fadeRunnable: Runnable? = null
    private var fadeWakeLock: PowerManager.WakeLock? = null
    private var activeChannel: MethodChannel? = null

    fun attachChannel(channel: MethodChannel?) {
        activeChannel = channel
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun setToastEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_TOAST_ENABLED, enabled).apply()
    }

    private fun showToastIfEnabled(context: Context, message: String) {
        if (!prefs(context).getBoolean(KEY_TOAST_ENABLED, true)) {
            return
        }
        val appCtx = context.applicationContext
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(appCtx, message, Toast.LENGTH_SHORT).show()
        }
    }

    fun isAdminActive(context: Context): Boolean {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val compName = ComponentName(context, MyDeviceAdminReceiver::class.java)
        return dpm.isAdminActive(compName)
    }

    fun muteAudio(context: Context): Int {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val p = prefs(context)
        val wasFading = p.getBoolean(KEY_IS_FADING, false)
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        if (!wasFading && currentVolume > 0) {
            p.edit().putInt(KEY_LAST_VOLUME, currentVolume).apply()
        }
        p.edit()
            .putBoolean(KEY_IS_FADING, false)
            .putInt(KEY_FADE_START_VOLUME, 0)
            .putBoolean(KEY_MUTED_BY_APP, true)
            .apply()
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, 0, 0)
        val saved = p.getInt(KEY_LAST_VOLUME, -1)
        return if (!wasFading && currentVolume > 0) currentVolume else maxOf(0, saved)
    }

    fun restoreAudio(context: Context): Int {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val p = prefs(context)
        val saved = p.getInt(KEY_LAST_VOLUME, -1)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val targetVolume = if (saved > 0) {
            saved
        } else {
            (maxVolume / 2).coerceAtLeast(1)
        }
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
        p.edit()
            .putBoolean(KEY_IS_FADING, false)
            .putInt(KEY_FADE_START_VOLUME, 0)
            .putBoolean(KEY_MUTED_BY_APP, false)
            .apply()
        return targetVolume
    }

    private fun acquireFadeWakeLock(context: Context, durationMs: Long) {
        try {
            val pm = context.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = fadeWakeLock ?: pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "EepyTime::VolumeFadeWakeLock"
            ).apply {
                setReferenceCounted(false)
                fadeWakeLock = this
            }
            wl.acquire((durationMs + 4_000L).coerceAtMost(30_000L))
        } catch (_: Exception) {
        }
    }

    private fun releaseFadeWakeLock() {
        try {
            if (fadeWakeLock?.isHeld == true) {
                fadeWakeLock?.release()
            }
        } catch (_: Exception) {
        }
    }

    private fun cancelFadeLoop(context: Context, restoreVolumeIfFading: Boolean) {
        fadeRunnable?.let { mainHandler.removeCallbacks(it) }
        fadeRunnable = null
        releaseFadeWakeLock()

        val appCtx = context.applicationContext
        val p = prefs(appCtx)
        val wasFading = p.getBoolean(KEY_IS_FADING, false)
        if (wasFading) {
            val startVol = p.getInt(KEY_FADE_START_VOLUME, 0)
            if (restoreVolumeIfFading && startVol > 0) {
                val audioManager = appCtx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, startVol, 0)
            }
            if (restoreVolumeIfFading) {
                p.edit()
                    .putBoolean(KEY_IS_FADING, false)
                    .putInt(KEY_FADE_START_VOLUME, 0)
                    .apply()
            }
        }
    }

    private fun applyFadeStep(context: Context, remainingMs: Long, fadeWindowMs: Long) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val p = prefs(context)
        val wasFading = p.getBoolean(KEY_IS_FADING, false)
        val currentVol = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)

        if (!wasFading) {
            val editor = p.edit()
                .putBoolean(KEY_IS_FADING, true)
                .putInt(KEY_FADE_START_VOLUME, currentVol)
            if (currentVol > 0) {
                editor.putInt(KEY_LAST_VOLUME, currentVol)
            }
            editor.apply()
        }

        val startVol = p.getInt(KEY_FADE_START_VOLUME, currentVol)
        if (startVol <= 0 || fadeWindowMs <= 0L) {
            return
        }

        val ratio = (remainingMs.toDouble() / fadeWindowMs.toDouble()).coerceIn(0.0, 1.0)
        val desiredVol = (startVol * ratio).roundToInt().coerceIn(0, startVol)
        if (desiredVol < currentVol) {
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, desiredVol, 0)
        }
    }

    fun syncVolumeFadeLoop(context: Context) {
        val appCtx = context.applicationContext
        fadeRunnable?.let { mainHandler.removeCallbacks(it) }
        fadeRunnable = null

        val p = prefs(appCtx)
        val status = p.getString(KEY_TIMER_STATUS, "idle") ?: "idle"
        val deadlineMs = p.getLong(KEY_DEADLINE_MS, 0L)
        val fadeWindowMs = p.getLong(KEY_FADE_WINDOW_MS, DEFAULT_FADE_WINDOW_MS)
            .coerceAtLeast(1_000L)

        if (status != "running" || deadlineMs <= 0L) {
            releaseFadeWakeLock()
            return
        }

        val runnable = object : Runnable {
            override fun run() {
                val curStatus = p.getString(KEY_TIMER_STATUS, "idle") ?: "idle"
                val curDeadline = p.getLong(KEY_DEADLINE_MS, 0L)
                val curFadeWindow = p.getLong(KEY_FADE_WINDOW_MS, DEFAULT_FADE_WINDOW_MS)
                    .coerceAtLeast(1_000L)
                if (curStatus != "running" || curDeadline <= 0L) {
                    releaseFadeWakeLock()
                    return
                }

                val remainingMs = curDeadline - System.currentTimeMillis()
                if (remainingMs <= 0L) {
                    releaseFadeWakeLock()
                    completeTimerFromNative(appCtx)
                    return
                }

                if (remainingMs > curFadeWindow) {
                    val waitMs = (remainingMs - curFadeWindow).coerceAtLeast(100L)
                    mainHandler.postDelayed(this, waitMs)
                } else {
                    acquireFadeWakeLock(appCtx, remainingMs)
                    applyFadeStep(appCtx, remainingMs, curFadeWindow)
                    mainHandler.postDelayed(this, FADE_TICK_INTERVAL_MS)
                }
            }
        }
        fadeRunnable = runnable
        mainHandler.post(runnable)
    }

    private fun newIsoFormat(): SimpleDateFormat {
        return SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).apply {
            timeZone = TimeZone.getDefault()
        }
    }

    @Synchronized
    fun onDeviceUnlockedOrPresent(
        context: Context,
        fromScreenOnOnly: Boolean = false,
        forceFinish: Boolean = false
    ): Boolean {
        val appCtx = context.applicationContext
        val p = prefs(appCtx)
        val status = p.getString(KEY_TIMER_STATUS, "idle") ?: "idle"

        if (status == "running") {
            return false
        }

        val km = appCtx.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (fromScreenOnOnly && km.isKeyguardLocked) {
            // Pengguna hanya menyalakan layar untuk melihat jam tanpa membuka kunci
            return false
        }

        var handled = false

        // 1. Jika sedang dalam Mode Tidur Aktif ("sleeping"), akhiri & catat durasi tidur aktual
        if (status == "sleeping") {
            val sleepStartMs = p.getLong(KEY_SLEEP_START_MS, 0L)
            val nowMs = System.currentTimeMillis()
            if (!forceFinish && sleepStartMs > 0L && (nowMs - sleepStartMs) < 2_500L) {
                // Abaikan broadcast transisi sesaat tepat ketika layar baru saja dikunci
                return false
            }
            if (!forceFinish && km.isKeyguardLocked) {
                return false
            }

            val sessionKey = p.getString(KEY_SLEEP_SESSION_KEY, "sleep_$sleepStartMs")
                ?: "sleep_$sleepStartMs"
            val presetLabel = p.getString(KEY_SLEEP_PRESET_LABEL, "EepyTime") ?: "EepyTime"
            val timerSeconds = p.getInt(KEY_SLEEP_TIMER_SECONDS, 0)
            val sleepStartIso = p.getString(KEY_SLEEP_START_ISO, "")
                ?.takeIf { it.isNotEmpty() }
                ?: newIsoFormat().format(Date(if (sleepStartMs > 0L) sleepStartMs else nowMs))
            val locked = p.getBoolean(KEY_SLEEP_LOCKED, true)
            val muted = p.getBoolean(KEY_SLEEP_MUTED, true)

            val wakeIso = newIsoFormat().format(Date(nowMs))
            val sleepDurationSec = if (sleepStartMs > 0L && nowMs > sleepStartMs) {
                ((nowMs - sleepStartMs) / 1000L).toInt().coerceAtLeast(1)
            } else {
                1
            }

            recordPendingCompletion(
                appCtx,
                sessionKey = sessionKey,
                presetLabel = presetLabel,
                durationSeconds = timerSeconds,
                executedAt = sleepStartIso,
                wokeUpAt = wakeIso,
                sleepDurationSeconds = sleepDurationSec,
                locked = locked,
                muted = muted
            )

            p.edit()
                .putString(KEY_TIMER_STATUS, "idle")
                .remove(KEY_SLEEP_SESSION_KEY)
                .remove(KEY_SLEEP_START_MS)
                .remove(KEY_SLEEP_START_ISO)
                .remove(KEY_SLEEP_PRESET_LABEL)
                .remove(KEY_SLEEP_TIMER_SECONDS)
                .remove(KEY_SLEEP_LOCKED)
                .remove(KEY_SLEEP_MUTED)
                .apply()

            TimerForegroundService.stop(appCtx)
            handled = true
        }

        // 2. Pulihkan volume media secara otomatis jika sebelumnya diredam oleh EepyTime
        var restoredVolume: Int? = null
        if (p.getBoolean(KEY_MUTED_BY_APP, false)) {
            val audioManager = appCtx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            if (current > 0) {
                p.edit().putBoolean(KEY_MUTED_BY_APP, false).apply()
            } else {
                restoredVolume = restoreAudio(appCtx)
                handled = true
            }
        }

        if (handled) {
            val toastMsg = if (restoredVolume != null) {
                "EepyTime: Durasi tidur tercatat & volume dipulihkan ke $restoredVolume"
            } else {
                "EepyTime: Sesi tidur selesai & tercatat"
            }
            showToastIfEnabled(appCtx, toastMsg)
            val extra = if (restoredVolume != null) {
                mapOf("restoredVolume" to restoredVolume)
            } else {
                emptyMap()
            }
            notifyDartStateChanged(appCtx, "sleepFinished", extra)
        }

        return handled
    }

    fun lockScreen(context: Context): Boolean {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val compName = ComponentName(context, MyDeviceAdminReceiver::class.java)
        return if (dpm.isAdminActive(compName)) {
            dpm.lockNow()
            true
        } else {
            false
        }
    }

    fun executeSleepAndMute(context: Context): Map<String, Boolean> {
        val appCtx = context.applicationContext
        val status = prefs(appCtx).getString(KEY_TIMER_STATUS, "idle") ?: "idle"
        if (status == "running" || status == "paused") {
            return completeTimerFromNative(appCtx)
        }
        cancelFadeLoop(appCtx, restoreVolumeIfFading = false)
        cancelTimerAlarms(appCtx)
        muteAudio(appCtx)
        val isLocked = lockScreen(appCtx)
        return mapOf(
            "muted" to true,
            "locked" to isLocked
        )
    }

    fun startTimer(
        context: Context,
        deadlineMs: Long,
        initialSeconds: Int,
        presetLabel: String,
        toastEnabled: Boolean
    ) {
        val appCtx = context.applicationContext
        if (prefs(appCtx).getString(KEY_TIMER_STATUS, "idle") == "sleeping") {
            onDeviceUnlockedOrPresent(appCtx, forceFinish = true)
        }
        cancelFadeLoop(appCtx, restoreVolumeIfFading = true)

        val runDurationMs = (deadlineMs - System.currentTimeMillis()).coerceAtLeast(1_000L)
        val fadeWindowMs = minOf(DEFAULT_FADE_WINDOW_MS, runDurationMs)

        prefs(appCtx).edit()
            .putString(KEY_TIMER_STATUS, "running")
            .putLong(KEY_DEADLINE_MS, deadlineMs)
            .putLong(KEY_FADE_WINDOW_MS, fadeWindowMs)
            .putBoolean(KEY_IS_FADING, false)
            .putInt(KEY_FADE_START_VOLUME, 0)
            .putInt(KEY_INITIAL_SECONDS, initialSeconds)
            .putInt(KEY_PAUSED_REMAINING_SECONDS, 0)
            .putString(KEY_PRESET_LABEL, presetLabel)
            .putBoolean(KEY_TOAST_ENABLED, toastEnabled)
            .apply()

        scheduleTimerAlarms(appCtx, deadlineMs, fadeWindowMs)
        TimerForegroundService.startOrUpdate(appCtx)
        syncVolumeFadeLoop(appCtx)
        showToastIfEnabled(appCtx, "EepyTime dimulai: $presetLabel")
    }

    fun pauseTimer(
        context: Context,
        remainingSeconds: Int,
        initialSeconds: Int,
        presetLabel: String
    ) {
        val appCtx = context.applicationContext
        cancelFadeLoop(appCtx, restoreVolumeIfFading = true)

        prefs(appCtx).edit()
            .putString(KEY_TIMER_STATUS, "paused")
            .putLong(KEY_DEADLINE_MS, 0L)
            .putInt(KEY_INITIAL_SECONDS, initialSeconds)
            .putInt(KEY_PAUSED_REMAINING_SECONDS, remainingSeconds.coerceAtLeast(0))
            .putString(KEY_PRESET_LABEL, presetLabel)
            .apply()

        cancelTimerAlarms(appCtx)
        TimerForegroundService.startOrUpdate(appCtx)
    }

    fun stopTimer(context: Context, notifyDart: Boolean = false) {
        val appCtx = context.applicationContext
        if (prefs(appCtx).getString(KEY_TIMER_STATUS, "idle") == "sleeping") {
            if (notifyDart) {
                onDeviceUnlockedOrPresent(appCtx, forceFinish = true)
            }
            return
        }
        cancelFadeLoop(appCtx, restoreVolumeIfFading = true)

        prefs(appCtx).edit()
            .putString(KEY_TIMER_STATUS, "idle")
            .putLong(KEY_DEADLINE_MS, 0L)
            .putInt(KEY_INITIAL_SECONDS, 0)
            .putInt(KEY_PAUSED_REMAINING_SECONDS, 0)
            .putString(KEY_PRESET_LABEL, "Pilih Durasi / Preset")
            .apply()

        cancelTimerAlarms(appCtx)
        TimerForegroundService.stop(appCtx)

        if (notifyDart) {
            showToastIfEnabled(appCtx, "EepyTime dihentikan")
            notifyDartStateChanged(appCtx, "timerStopped")
        }
    }

    fun extendTimer(context: Context, additionalSeconds: Int = 600, notifyDart: Boolean = true) {
        val appCtx = context.applicationContext
        val p = prefs(appCtx)
        val status = p.getString(KEY_TIMER_STATUS, "idle") ?: "idle"
        val currentInitial = p.getInt(KEY_INITIAL_SECONDS, 900)
        val newInitial = currentInitial + additionalSeconds

        if (status == "running") {
            cancelFadeLoop(appCtx, restoreVolumeIfFading = true)

            val now = System.currentTimeMillis()
            val currentDeadline = p.getLong(KEY_DEADLINE_MS, now)
            val base = if (currentDeadline > now) currentDeadline else now
            val newDeadline = base + (additionalSeconds * 1000L)
            val runDurationMs = (newDeadline - now).coerceAtLeast(1_000L)
            val fadeWindowMs = minOf(DEFAULT_FADE_WINDOW_MS, runDurationMs)

            p.edit()
                .putLong(KEY_DEADLINE_MS, newDeadline)
                .putLong(KEY_FADE_WINDOW_MS, fadeWindowMs)
                .putInt(KEY_INITIAL_SECONDS, newInitial)
                .apply()

            scheduleTimerAlarms(appCtx, newDeadline, fadeWindowMs)
            TimerForegroundService.startOrUpdate(appCtx)
            syncVolumeFadeLoop(appCtx)
        } else if (status == "paused") {
            val pausedRem = p.getInt(KEY_PAUSED_REMAINING_SECONDS, 0) + additionalSeconds
            p.edit()
                .putInt(KEY_PAUSED_REMAINING_SECONDS, pausedRem)
                .putInt(KEY_INITIAL_SECONDS, newInitial)
                .apply()
            TimerForegroundService.startOrUpdate(appCtx)
        }

        if (notifyDart) {
            val addedMin = additionalSeconds / 60
            showToastIfEnabled(appCtx, "EepyTime diperpanjang +$addedMin menit")
            notifyDartStateChanged(
                appCtx,
                "timerExtended",
                mapOf("addedSeconds" to additionalSeconds)
            )
        }
    }

    @Synchronized
    fun completeTimerFromNative(context: Context): Map<String, Boolean> {
        val appCtx = context.applicationContext
        val p = prefs(appCtx)
        val status = p.getString(KEY_TIMER_STATUS, "idle") ?: "idle"
        if (status != "running" && status != "paused") {
            return mapOf(
                "muted" to p.getBoolean(KEY_MUTED_BY_APP, true),
                "locked" to isAdminActive(appCtx)
            )
        }

        val initialSeconds = p.getInt(KEY_INITIAL_SECONDS, 0)
        val presetLabel = p.getString(KEY_PRESET_LABEL, "EepyTime")
            ?.takeIf { it.isNotEmpty() && it != "Pilih Durasi / Preset" }
            ?: "EepyTime"

        cancelFadeLoop(appCtx, restoreVolumeIfFading = false)
        cancelTimerAlarms(appCtx)

        muteAudio(appCtx)
        val locked = lockScreen(appCtx)
        val muted = true

        val sleepStartMs = System.currentTimeMillis()
        val sleepStartIso = newIsoFormat().format(Date(sleepStartMs))
        val sessionKey = "sleep_$sleepStartMs"

        p.edit()
            .putString(KEY_TIMER_STATUS, "sleeping")
            .putLong(KEY_DEADLINE_MS, 0L)
            .putInt(KEY_INITIAL_SECONDS, 0)
            .putInt(KEY_PAUSED_REMAINING_SECONDS, 0)
            .putString(KEY_PRESET_LABEL, "Pilih Durasi / Preset")
            .putString(KEY_SLEEP_SESSION_KEY, sessionKey)
            .putLong(KEY_SLEEP_START_MS, sleepStartMs)
            .putString(KEY_SLEEP_START_ISO, sleepStartIso)
            .putString(KEY_SLEEP_PRESET_LABEL, presetLabel)
            .putInt(KEY_SLEEP_TIMER_SECONDS, initialSeconds)
            .putBoolean(KEY_SLEEP_LOCKED, locked)
            .putBoolean(KEY_SLEEP_MUTED, muted)
            .apply()

        // Pertahankan service dalam Mode Tidur Aktif agar deteksi buka kunci (bangun tidur)
        // dan pemulihan volume tetap berjalan 100% akurat semalaman.
        TimerForegroundService.startOrUpdate(appCtx)

        showToastIfEnabled(
            appCtx,
            if (locked) "EepyTime: Layar dikunci • Menghitung waktu tidur..."
            else "EepyTime: Suara diredam • Menghitung waktu tidur..."
        )

        notifyDartStateChanged(
            appCtx,
            "sleepStarted",
            mapOf(
                "muted" to muted,
                "locked" to locked,
                "presetLabel" to presetLabel,
                "durationSeconds" to initialSeconds
            )
        )

        return mapOf(
            "muted" to muted,
            "locked" to locked
        )
    }

    private fun recordPendingCompletion(
        context: Context,
        sessionKey: String,
        presetLabel: String,
        durationSeconds: Int,
        executedAt: String,
        wokeUpAt: String,
        sleepDurationSeconds: Int,
        locked: Boolean,
        muted: Boolean
    ) {
        val p = prefs(context)
        val raw = p.getString(KEY_PENDING_COMPLETIONS, "[]") ?: "[]"
        val arr = try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
        val obj = JSONObject().apply {
            put("sessionKey", sessionKey)
            put("presetLabel", presetLabel)
            put("durationSeconds", durationSeconds)
            put("executedAt", executedAt)
            put("wokeUpAt", wokeUpAt)
            put("sleepDurationSeconds", sleepDurationSeconds)
            put("isScreenLocked", locked)
            put("isAudioMuted", muted)
        }
        arr.put(obj)
        p.edit().putString(KEY_PENDING_COMPLETIONS, arr.toString()).apply()
    }

    fun consumePendingCompletions(context: Context): List<Map<String, Any>> {
        val p = prefs(context)
        val raw = p.getString(KEY_PENDING_COMPLETIONS, "[]") ?: "[]"
        if (raw == "[]") {
            return emptyList()
        }
        p.edit().putString(KEY_PENDING_COMPLETIONS, "[]").apply()
        val list = mutableListOf<Map<String, Any>>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val item = arr.getJSONObject(i)
                list.add(
                    mapOf(
                        "sessionKey" to item.optString("sessionKey", ""),
                        "presetLabel" to item.optString("presetLabel", "EepyTime"),
                        "durationSeconds" to item.optInt("durationSeconds", 0),
                        "executedAt" to item.optString("executedAt", ""),
                        "wokeUpAt" to item.optString("wokeUpAt", ""),
                        "sleepDurationSeconds" to item.optInt("sleepDurationSeconds", 0),
                        "isScreenLocked" to item.optBoolean("isScreenLocked", true),
                        "isAudioMuted" to item.optBoolean("isAudioMuted", true)
                    )
                )
            }
        } catch (_: Exception) {
        }
        return list
    }

    fun getTimerState(context: Context): Map<String, Any> {
        val p = prefs(context)
        var status = p.getString(KEY_TIMER_STATUS, "idle") ?: "idle"
        val deadlineMs = p.getLong(KEY_DEADLINE_MS, 0L)

        if (status == "running" && deadlineMs > 0L && System.currentTimeMillis() >= deadlineMs) {
            completeTimerFromNative(context)
            status = p.getString(KEY_TIMER_STATUS, "idle") ?: "idle"
        }

        // Jika ponsel saat ini sudah dibuka kuncinya (unlocked) setelah melewati masa tenggang kunci,
        // selesaikan sesi tidur aktif secara otomatis.
        if (status == "sleeping") {
            val sleepStartMs = p.getLong(KEY_SLEEP_START_MS, 0L)
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (!km.isKeyguardLocked && System.currentTimeMillis() - sleepStartMs >= 2_500L) {
                onDeviceUnlockedOrPresent(context, fromScreenOnOnly = false, forceFinish = false)
                status = p.getString(KEY_TIMER_STATUS, "idle") ?: "idle"
            }
        }

        val initialSeconds = p.getInt(KEY_INITIAL_SECONDS, 0)
        val pausedRemaining = p.getInt(KEY_PAUSED_REMAINING_SECONDS, 0)
        val presetLabel = p.getString(KEY_PRESET_LABEL, "Pilih Durasi / Preset")
            ?: "Pilih Durasi / Preset"
        val isMuted = p.getBoolean(KEY_MUTED_BY_APP, false)

        return mapOf(
            "status" to status,
            "deadlineMs" to deadlineMs,
            "initialSeconds" to initialSeconds,
            "pausedRemainingSeconds" to pausedRemaining,
            "presetLabel" to presetLabel,
            "isMuted" to isMuted,
            "pendingCompletions" to consumePendingCompletions(context)
        )
    }

    private fun notifyDartStateChanged(
        context: Context,
        event: String,
        extra: Map<String, Any> = emptyMap()
    ) {
        val channel = activeChannel ?: return
        val payload = HashMap<String, Any>(getTimerState(context))
        payload["event"] = event
        payload.putAll(extra)
        try {
            channel.invokeMethod("onNativeTimerEvent", payload)
        } catch (_: Exception) {
        }
    }

    private fun setExactAlarmCompat(alarmManager: AlarmManager, triggerAtMs: Long, pi: PendingIntent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            } else {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            }
        } catch (_: SecurityException) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
        }
    }

    private fun scheduleTimerAlarms(context: Context, deadlineMs: Long, fadeWindowMs: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val deadlineIntent = Intent(context, TimerActionReceiver::class.java).apply {
            action = ACTION_DEADLINE_ALARM
            setPackage(context.packageName)
        }
        val deadlinePi = PendingIntent.getBroadcast(
            context,
            2001,
            deadlineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        setExactAlarmCompat(alarmManager, deadlineMs, deadlinePi)

        val fadeStartIntent = Intent(context, TimerActionReceiver::class.java).apply {
            action = ACTION_FADE_START_ALARM
            setPackage(context.packageName)
        }
        val fadeStartPi = PendingIntent.getBroadcast(
            context,
            2002,
            fadeStartIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val fadeStartAtMs = deadlineMs - fadeWindowMs
        if (fadeStartAtMs > System.currentTimeMillis() + 500L) {
            setExactAlarmCompat(alarmManager, fadeStartAtMs, fadeStartPi)
        } else {
            alarmManager.cancel(fadeStartPi)
        }
    }

    private fun cancelTimerAlarms(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val deadlineIntent = Intent(context, TimerActionReceiver::class.java).apply {
            action = ACTION_DEADLINE_ALARM
            setPackage(context.packageName)
        }
        val deadlinePi = PendingIntent.getBroadcast(
            context,
            2001,
            deadlineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(deadlinePi)

        val fadeStartIntent = Intent(context, TimerActionReceiver::class.java).apply {
            action = ACTION_FADE_START_ALARM
            setPackage(context.packageName)
        }
        val fadeStartPi = PendingIntent.getBroadcast(
            context,
            2002,
            fadeStartIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(fadeStartPi)
    }

    fun ensureNotificationChannel(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = nm.getNotificationChannel(NOTIFICATION_CHANNEL_ID)
        if (existing == null) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "EepyTime Countdown",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Menampilkan sisa waktu hitung mundur EepyTime dan kontrol cepat."
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            nm.createNotificationChannel(channel)
        }
    }

    fun buildTimerNotification(context: Context): Notification {
        ensureNotificationChannel(context)
        val p = prefs(context)
        val status = p.getString(KEY_TIMER_STATUS, "running") ?: "running"
        val deadlineMs = p.getLong(KEY_DEADLINE_MS, System.currentTimeMillis())
        val pausedRem = p.getInt(KEY_PAUSED_REMAINING_SECONDS, 0)
        val label = p.getString(KEY_PRESET_LABEL, "EepyTime") ?: "EepyTime"

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPi = PendingIntent.getActivity(
            context,
            100,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        fun actionPi(reqCode: Int, actionStr: String): PendingIntent {
            val i = Intent(context, TimerActionReceiver::class.java).apply {
                action = actionStr
                setPackage(context.packageName)
            }
            return PendingIntent.getBroadcast(
                context,
                reqCode,
                i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val builder = Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
        val sleepStartMs = p.getLong(KEY_SLEEP_START_MS, System.currentTimeMillis())

        val title = when (status) {
            "sleeping" -> "EepyTime • Mode Tidur Aktif"
            "paused" -> "EepyTime (Dijeda • ${formatDuration(pausedRem)})"
            else -> "EepyTime"
        }
        val subtitle = if (status == "sleeping") {
            "Menghitung durasi tidur hingga layar dibuka kembali"
        } else {
            label
        }

        builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setContentIntent(contentPi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        if (status == "running" && deadlineMs > System.currentTimeMillis()) {
            builder.setWhen(deadlineMs)
            builder.setShowWhen(true)
            builder.setUsesChronometer(true)
            builder.setChronometerCountDown(true)
        } else if (status == "sleeping") {
            builder.setWhen(sleepStartMs)
            builder.setShowWhen(true)
            builder.setUsesChronometer(true)
            builder.setChronometerCountDown(false)
        } else {
            builder.setShowWhen(false)
            builder.setUsesChronometer(false)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        if (status == "sleeping") {
            val finishSleepAction = Notification.Action.Builder(
                0,
                "Selesai Tidur",
                actionPi(104, ACTION_FINISH_SLEEP)
            ).build()
            builder.addAction(finishSleepAction)
        } else {
            val stopAction = Notification.Action.Builder(
                0,
                "Stop",
                actionPi(101, ACTION_STOP)
            ).build()

            val sleepNowAction = Notification.Action.Builder(
                0,
                "Tidur Sekarang",
                actionPi(102, ACTION_SLEEP_NOW)
            ).build()

            val extendAction = Notification.Action.Builder(
                0,
                "+10 Menit",
                actionPi(103, ACTION_EXTEND_10M)
            ).build()

            builder.addAction(stopAction)
            builder.addAction(sleepNowAction)
            builder.addAction(extendAction)
        }

        return builder.build()
    }

    private fun formatDuration(totalSeconds: Int): String {
        val safe = totalSeconds.coerceAtLeast(0)
        val h = safe / 3600
        val m = (safe % 3600) / 60
        val s = safe % 60
        return String.format(Locale.US, "%02d:%02d:%02d", h, m, s)
    }
}

class TimerActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        when (action) {
            NativeTimerManager.ACTION_STOP -> {
                NativeTimerManager.stopTimer(context, notifyDart = true)
            }
            NativeTimerManager.ACTION_SLEEP_NOW -> {
                NativeTimerManager.completeTimerFromNative(context)
            }
            NativeTimerManager.ACTION_EXTEND_10M -> {
                NativeTimerManager.extendTimer(context, additionalSeconds = 600, notifyDart = true)
            }
            NativeTimerManager.ACTION_FINISH_SLEEP -> {
                NativeTimerManager.onDeviceUnlockedOrPresent(context, forceFinish = true)
            }
            NativeTimerManager.ACTION_FADE_START_ALARM -> {
                TimerForegroundService.startOrUpdate(context)
                NativeTimerManager.syncVolumeFadeLoop(context)
            }
            NativeTimerManager.ACTION_DEADLINE_ALARM -> {
                NativeTimerManager.completeTimerFromNative(context)
            }
        }
    }
}

class TimerForegroundService : Service() {
    companion object {
        fun startOrUpdate(context: Context) {
            val intent = Intent(context, TimerForegroundService::class.java)
            try {
                context.startForegroundService(intent)
            } catch (_: Exception) {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(
                    NativeTimerManager.NOTIFICATION_ID,
                    NativeTimerManager.buildTimerNotification(context)
                )
            }
        }

        fun stop(context: Context) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(NativeTimerManager.NOTIFICATION_ID)
            try {
                context.stopService(Intent(context, TimerForegroundService::class.java))
            } catch (_: Exception) {
            }
        }
    }

    private var unlockReceiverRegistered = false

    private val unlockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val ctx = context ?: return
            when (intent?.action) {
                Intent.ACTION_USER_PRESENT -> {
                    NativeTimerManager.onDeviceUnlockedOrPresent(ctx, fromScreenOnOnly = false)
                }
                Intent.ACTION_SCREEN_ON -> {
                    NativeTimerManager.onDeviceUnlockedOrPresent(ctx, fromScreenOnOnly = true)
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        registerUnlockReceiverIfNeeded()
    }

    override fun onDestroy() {
        if (unlockReceiverRegistered) {
            try {
                unregisterReceiver(unlockReceiver)
            } catch (_: Exception) {
            }
            unlockReceiverRegistered = false
        }
        super.onDestroy()
    }

    private fun registerUnlockReceiverIfNeeded() {
        if (unlockReceiverRegistered) {
            return
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(unlockReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(unlockReceiver, filter)
            }
            unlockReceiverRegistered = true
        } catch (_: Exception) {
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        registerUnlockReceiverIfNeeded()
        val notification = NativeTimerManager.buildTimerNotification(this)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NativeTimerManager.NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NativeTimerManager.NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
        }
        NativeTimerManager.syncVolumeFadeLoop(this)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

class MainActivity : FlutterActivity() {
    private var methodChannel: MethodChannel? = null

    private val userPresentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_USER_PRESENT && context != null) {
                NativeTimerManager.onDeviceUnlockedOrPresent(context, fromScreenOnOnly = false)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(userPresentReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(userPresentReceiver, filter)
        }
        requestNotificationPermissionIfNeeded()
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(userPresentReceiver)
        } catch (_: Exception) {
        }
        NativeTimerManager.attachChannel(null)
        super.onDestroy()
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    3001
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val compName = ComponentName(this, MyDeviceAdminReceiver::class.java)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeTimerManager.CHANNEL_NAME
        )
        methodChannel = channel
        NativeTimerManager.attachChannel(channel)

        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "checkAdmin" -> {
                        result.success(NativeTimerManager.isAdminActive(this))
                    }
                    "requestAdmin" -> {
                        if (!dpm.isAdminActive(compName)) {
                            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, compName)
                                putExtra(
                                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                    "Izin Device Administrator diperlukan agar EepyTime dapat mengunci layar perangkat secara otomatis saat waktu hitung mundur habis."
                                )
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    "revokeAdmin" -> {
                        if (dpm.isAdminActive(compName)) {
                            dpm.removeActiveAdmin(compName)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "muteAudio" -> {
                        result.success(NativeTimerManager.muteAudio(this))
                    }
                    "restoreAudio" -> {
                        result.success(NativeTimerManager.restoreAudio(this))
                    }
                    "lockScreen" -> {
                        result.success(NativeTimerManager.lockScreen(this))
                    }
                    "executeSleepAndMute" -> {
                        result.success(NativeTimerManager.executeSleepAndMute(this))
                    }
                    "startNativeTimer" -> {
                        val deadlineMs = (call.argument<Number>("deadlineMs"))?.toLong()
                            ?: (System.currentTimeMillis() + 900_000L)
                        val initialSeconds = call.argument<Int>("initialSeconds") ?: 900
                        val presetLabel = call.argument<String>("presetLabel")
                            ?: "Tidur Cepat (15 Menit)"
                        val toastEnabled = call.argument<Boolean>("toastEnabled") ?: true
                        requestNotificationPermissionIfNeeded()
                        NativeTimerManager.startTimer(
                            this,
                            deadlineMs = deadlineMs,
                            initialSeconds = initialSeconds,
                            presetLabel = presetLabel,
                            toastEnabled = toastEnabled
                        )
                        result.success(true)
                    }
                    "pauseNativeTimer" -> {
                        val remainingSeconds = call.argument<Int>("remainingSeconds") ?: 0
                        val initialSeconds = call.argument<Int>("initialSeconds") ?: 900
                        val presetLabel = call.argument<String>("presetLabel")
                            ?: "Tidur Cepat (15 Menit)"
                        NativeTimerManager.pauseTimer(
                            this,
                            remainingSeconds = remainingSeconds,
                            initialSeconds = initialSeconds,
                            presetLabel = presetLabel
                        )
                        result.success(true)
                    }
                    "stopNativeTimer" -> {
                        NativeTimerManager.stopTimer(this, notifyDart = false)
                        result.success(true)
                    }
                    "extendNativeTimer" -> {
                        val additionalSeconds = call.argument<Int>("additionalSeconds") ?: 600
                        NativeTimerManager.extendTimer(
                            this,
                            additionalSeconds = additionalSeconds,
                            notifyDart = false
                        )
                        result.success(true)
                    }
                    "setNativeToastEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        NativeTimerManager.setToastEnabled(this, enabled)
                        result.success(true)
                    }
                    "getNativeTimerState" -> {
                        result.success(NativeTimerManager.getTimerState(this))
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                result.error(
                    "NATIVE_ERROR",
                    e.localizedMessage ?: "Terjadi kesalahan pada layer native Android",
                    null
                )
            }
        }
    }
}
