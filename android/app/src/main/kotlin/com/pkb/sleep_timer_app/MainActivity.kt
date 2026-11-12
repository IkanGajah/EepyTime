package com.pkb.sleep_timer_app

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MyDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Toast.makeText(
            context,
            "Izin Kunci Layar (Device Admin) diaktifkan",
            Toast.LENGTH_SHORT
        ).show()
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Toast.makeText(
            context,
            "Izin Kunci Layar (Device Admin) dinonaktifkan",
            Toast.LENGTH_SHORT
        ).show()
    }
}

class MainActivity : FlutterActivity() {
    private val channelName = "sleep_timer/native_control"
    private var lastVolumeLevel: Int = -1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val compName = ComponentName(this, MyDeviceAdminReceiver::class.java)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "checkAdmin" -> {
                            val isActive = dpm.isAdminActive(compName)
                            result.success(isActive)
                        }
                        "requestAdmin" -> {
                            if (!dpm.isAdminActive(compName)) {
                                val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                                    putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, compName)
                                    putExtra(
                                        DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                        "Izin Device Administrator diperlukan agar aplikasi Timer Tidur Otomatis dapat mengunci layar perangkat secara otomatis saat waktu hitung mundur habis."
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
                            val previousVolume = performMuteAudio(audioManager)
                            result.success(previousVolume)
                        }
                        "restoreAudio" -> {
                            val restoredVolume = performRestoreAudio(audioManager)
                            result.success(restoredVolume)
                        }
                        "lockScreen" -> {
                            val isLocked = performLockScreen(dpm, compName)
                            result.success(isLocked)
                        }
                        "executeSleepAndMute" -> {
                            performMuteAudio(audioManager)
                            val isLocked = performLockScreen(dpm, compName)
                            val response = mapOf(
                                "muted" to true,
                                "locked" to isLocked
                            )
                            result.success(response)
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

    private fun performMuteAudio(audioManager: AudioManager): Int {
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        if (currentVolume > 0) {
            lastVolumeLevel = currentVolume
        }
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, 0, 0)
        return if (currentVolume > 0) currentVolume else maxOf(0, lastVolumeLevel)
    }

    private fun performRestoreAudio(audioManager: AudioManager): Int {
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val targetVolume = if (lastVolumeLevel > 0) {
            lastVolumeLevel
        } else {
            (maxVolume / 2).coerceAtLeast(1)
        }
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
        return targetVolume
    }

    private fun performLockScreen(dpm: DevicePolicyManager, compName: ComponentName): Boolean {
        return if (dpm.isAdminActive(compName)) {
            dpm.lockNow()
            true
        } else {
            false
        }
    }
}
