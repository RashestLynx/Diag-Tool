package com.rashestlynx.diag_tool

import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.rashestlynx.diag_tool/android"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "batteryExtras" -> result.success(batteryExtras())
                "deviceExtras" -> result.success(deviceExtras())
                else -> result.notImplemented()
            }
        }
    }

    // Battery temperature, health and charge-cycle count straight from the OS.
    private fun batteryExtras(): Map<String, Any?> {
        val status: Intent? = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val temperature = status?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        val healthCode = status?.getIntExtra(BatteryManager.EXTRA_HEALTH, 0) ?: 0

        var cycleCount = -1
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            cycleCount = status?.getIntExtra(BatteryManager.EXTRA_CYCLE_COUNT, -1) ?: -1
        }

        return mapOf(
            "temperature" to temperature, // tenths of a degree C
            "health" to healthLabel(healthCode),
            "cycleCount" to cycleCount
        )
    }

    // SoC manufacturer/model (Android 12+), board platform codename, and the
    // number of CPU cores the runtime sees.
    private fun deviceExtras(): Map<String, Any?> {
        val socMfr = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S)
            android.os.Build.SOC_MANUFACTURER else ""
        val socModel = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S)
            android.os.Build.SOC_MODEL else ""
        return mapOf(
            "socManufacturer" to socMfr,
            "socModel" to socModel,
            "board" to android.os.Build.BOARD,
            "cores" to Runtime.getRuntime().availableProcessors()
        )
    }

    private fun healthLabel(code: Int): String = when (code) {
        BatteryManager.BATTERY_HEALTH_GOOD -> "good"
        BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheat"
        BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
        BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "over_voltage"
        BatteryManager.BATTERY_HEALTH_COLD -> "cold"
        BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "failure"
        else -> "unknown"
    }
}
