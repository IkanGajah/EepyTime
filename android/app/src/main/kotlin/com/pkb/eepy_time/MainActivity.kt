package com.pkb.eepy_time

import android.Manifest
import android.app.AlarmManager
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

    private const val KEY_LAST_VOLUME = "last_volume_level"
    private const val KEY_MUTED_BY_APP = "muted_by_app"
    private const val KEY_TIMER_STATUS = "timer_status" // "idle" | "running" | "paused"
    private const val KEY_DEADLINE_MS = "deadline_ms"
    private const val KEY_INITIAL_SECONDS = "initial_seconds"
    private const val KEY_PAUSED_REMAINING_SECONDS = "paused_remaining_seconds"
    private const val KEY_PRESET_LABEL = "preset_label"
    private const val KEY_TOAST_ENABLED = "toast_enabled"
    private const val KEY_PENDING_COMPLETIONS = "pending_completions"

    const val ACTION_STOP = "com.pkb.eepy_time.ACTION_STOP"
    const val ACTION_SLEEP_NOW = "com.pkb.eepy_time.ACTION_SLEEP_NOW"
    const val ACTION_EXTEND_10M = "com.pkb.eepy_time.ACTION_EXTEND_10M"
    const val ACTION_DEADLINE_ALARM = "com.pkb.eepy_time.ACTION_DEADLINE_ALARM"

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
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        if (currentVolume > 0) {
            p.edit().putInt(KEY_LAST_VOLUME, currentVolume).apply()
        }
        p.edit().putBoolean(KEY_MUTED_BY_APP, true).apply()
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, 0, 0)
        val saved = p.getInt(KEY_LAST_VOLUME, -1)
        return if (currentVolume > 0) currentVolume else maxOf(0, saved)
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
        p.edit().putBoolean(KEY_MUTED_BY_APP, false).apply()
        return targetVolume
    }

    fun restoreAudioOnUserPresentIfNeeded(context: Context): Boolean {
        val p = prefs(context)
        if (!p.getBoolean(KEY_MUTED_BY_APP, false)) {
            return false
        }
        if (p.getString(KEY_TIMER_STATUS, "idle") == "running") {
            return false
        }
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        if (current > 0) {
            p.edit().putBoolean(KEY_MUTED_BY_APP, false).apply()
            notifyDartStateChanged(context, "volumeRestored")
            return false
        }
        val restored = restoreAudio(context)
        showToastIfEnabled(context, "EepyTime: Volume media dipulihkan ke $restored")
        notifyDartStateChanged(context, "volumeRestored", mapOf("restoredVolume" to restored))
        return true
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
        muteAudio(context)
        val isLocked = lockScreen(context)
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
        prefs(appCtx).edit()
            .putString(KEY_TIMER_STATUS, "running")
            .putLong(KEY_DEADLINE_MS, deadlineMs)
            .putInt(KEY_INITIAL_SECONDS, initialSeconds)
            .putInt(KEY_PAUSED_REMAINING_SECONDS, 0)
            .putString(KEY_PRESET_LABEL, presetLabel)
            .putBoolean(KEY_TOAST_ENABLED, toastEnabled)
            .apply()

        scheduleExactDeadlineAlarm(appCtx, deadlineMs)
        TimerForegroundService.startOrUpdate(appCtx)
        showToastIfEnabled(appCtx, "EepyTime dimulai: $presetLabel")
    }

    fun pauseTimer(
        context: Context,
        remainingSeconds: Int,
        initialSeconds: Int,
        presetLabel: String
    ) {
        val appCtx = context.applicationContext
        prefs(appCtx).edit()
            .putString(KEY_TIMER_STATUS, "paused")
            .putLong(KEY_DEADLINE_MS, 0L)
            .putInt(KEY_INITIAL_SECONDS, initialSeconds)
            .putInt(KEY_PAUSED_REMAINING_SECONDS, remainingSeconds.coerceAtLeast(0))
            .putString(KEY_PRESET_LABEL, presetLabel)
            .apply()

        cancelDeadlineAlarm(appCtx)
        TimerForegroundService.startOrUpdate(appCtx)
    }

    fun stopTimer(context: Context, notifyDart: Boolean = false) {
        val appCtx = context.applicationContext
        prefs(appCtx).edit()
            .putString(KEY_TIMER_STATUS, "idle")
            .putLong(KEY_DEADLINE_MS, 0L)
            .putInt(KEY_INITIAL_SECONDS, 0)
            .putInt(KEY_PAUSED_REMAINING_SECONDS, 0)
            .putString(KEY_PRESET_LABEL, "Pilih Durasi / Preset")
            .apply()

        cancelDeadlineAlarm(appCtx)
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
            val now = System.currentTimeMillis()
            val currentDeadline = p.getLong(KEY_DEADLINE_MS, now)
            val base = if (currentDeadline > now) currentDeadline else now
            val newDeadline = base + (additionalSeconds * 1000L)

            p.edit()
                .putLong(KEY_DEADLINE_MS, newDeadline)
                .putInt(KEY_INITIAL_SECONDS, newInitial)
                .apply()

            scheduleExactDeadlineAlarm(appCtx, newDeadline)
            TimerForegroundService.startOrUpdate(appCtx)
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

    fun completeTimerFromNative(context: Context) {
        val appCtx = context.applicationContext
        val p = prefs(appCtx)
        val status = p.getString(KEY_TIMER_STATUS, "idle") ?: "idle"
        if (status == "idle") {
            TimerForegroundService.stop(appCtx)
            return
        }

        val initialSeconds = p.getInt(KEY_INITIAL_SECONDS, 900)
        val presetLabel = p.getString(KEY_PRESET_LABEL, "Tidur Cepat (15 Menit)")
            ?: "Tidur Cepat (15 Menit)"

        p.edit()
            .putString(KEY_TIMER_STATUS, "idle")
            .putLong(KEY_DEADLINE_MS, 0L)
            .putInt(KEY_INITIAL_SECONDS, 0)
            .putInt(KEY_PAUSED_REMAINING_SECONDS, 0)
            .putString(KEY_PRESET_LABEL, "Pilih Durasi / Preset")
            .apply()

        cancelDeadlineAlarm(appCtx)
        TimerForegroundService.stop(appCtx)

        val result = executeSleepAndMute(appCtx)
        val muted = result["muted"] == true
        val locked = result["locked"] == true

        showToastIfEnabled(
            appCtx,
            if (locked) "EepyTime selesai: Suara diredam & layar dikunci"
            else "EepyTime selesai: Suara media diredam"
        )

        recordPendingCompletion(
            appCtx,
            presetLabel = presetLabel,
            durationSeconds = initialSeconds,
            locked = locked,
            muted = muted
        )

        notifyDartStateChanged(
            appCtx,
            "timerCompleted",
            mapOf(
                "muted" to muted,
                "locked" to locked,
                "presetLabel" to presetLabel,
                "durationSeconds" to initialSeconds
            )
        )
    }

    private fun recordPendingCompletion(
        context: Context,
        presetLabel: String,
        durationSeconds: Int,
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
        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
        isoFormat.timeZone = TimeZone.getDefault()
        val obj = JSONObject().apply {
            put("presetLabel", presetLabel)
            put("durationSeconds", durationSeconds)
            put("executedAt", isoFormat.format(Date()))
            put("isScreenLocked", locked)
            put("isAudioMuted", muted)
        }
        arr.put(obj)
        p.edit().putString(KEY_PENDING_COMPLETIONS, arr.toString()).apply()
    }

    fun consumePendingCompletions(context: Context): List<Map<String, Any>> {
        val p = prefs(context)
        val raw = p.getString(KEY_PENDING_COMPLETIONS, "[]") ?: "[]"
        p.edit().putString(KEY_PENDING_COMPLETIONS, "[]").apply()
        val list = mutableListOf<Map<String, Any>>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val item = arr.getJSONObject(i)
                list.add(
                    mapOf(
                        "presetLabel" to item.optString("presetLabel", "EepyTime"),
                        "durationSeconds" to item.optInt("durationSeconds", 900),
                        "executedAt" to item.optString("executedAt", ""),
                        "isScreenLocked" to item.optBoolean("isScreenLocked", false),
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
        val initialSeconds = p.getInt(KEY_INITIAL_SECONDS, 0)
        val pausedRemaining = p.getInt(KEY_PAUSED_REMAINING_SECONDS, 0)
        val presetLabel = p.getString(KEY_PRESET_LABEL, "Pilih Durasi / Preset")
            ?: "Pilih Durasi / Preset"
        val isMuted = p.getBoolean(KEY_MUTED_BY_APP, false)

        if (status == "running" && deadlineMs > 0L && System.currentTimeMillis() >= deadlineMs) {
            completeTimerFromNative(context)
            status = "idle"
        }

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

    private fun scheduleExactDeadlineAlarm(context: Context, deadlineMs: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, TimerActionReceiver::class.java).apply {
            action = ACTION_DEADLINE_ALARM
            setPackage(context.packageName)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            2001,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineMs, pi)
            } else {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineMs, pi)
            }
        } catch (_: SecurityException) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadlineMs, pi)
        }
    }

    private fun cancelDeadlineAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, TimerActionReceiver::class.java).apply {
            action = ACTION_DEADLINE_ALARM
            setPackage(context.packageName)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            2001,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pi)
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

        val title = if (status == "paused") {
            "EepyTime (Dijeda • ${formatDuration(pausedRem)})"
        } else {
            "EepyTime"
        }

        builder
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(label)
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
        } else {
            builder.setShowWhen(false)
            builder.setUsesChronometer(false)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

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

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
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
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

class MainActivity : FlutterActivity() {
    private var methodChannel: MethodChannel? = null

    private val userPresentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_USER_PRESENT && context != null) {
                NativeTimerManager.restoreAudioOnUserPresentIfNeeded(context)
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
