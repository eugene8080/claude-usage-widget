package com.usage.claudewidget.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import com.usage.claudewidget.data.Storage

/**
 * Whether this phone lets the app do its job in the background, and shortcuts to the
 * settings that decide it.
 *
 * Two independent layers can stop the 15-minute refresh and the watch send:
 *  1. Android's battery optimisation - readable via PowerManager, and the app can ask for
 *     an exemption directly.
 *  2. The manufacturer's own background manager. ColorOS (Oppo / OnePlus / realme) freezes
 *     a background app ~5 s after waking it (its "OFreezer"), which let the fetch and the
 *     widget finish but cut off the Bluetooth send every time on an Oppo Find N5
 *     (2026-09-25). Its "Allow background activity" switch has no public API, so the app
 *     cannot read it - it can only point the user at it, and notice afterwards when a send
 *     is still being stopped (Storage.watchPushStoppedBySystem).
 */
object BackgroundAccess {

    private const val TAG = "BackgroundAccess"
    const val GARMIN_CONNECT_PACKAGE = "com.garmin.android.apps.connectmobile"

    /** Manufacturers that ship ColorOS and its aggressive background freezer. */
    private val COLOROS_MANUFACTURERS = setOf("oppo", "oneplus", "realme")

    data class Status(
        /** Android battery optimisation is off for this app. */
        val batteryExempt: Boolean,
        /** The phone runs ColorOS, whose own background setting must also be changed. */
        val colorOs: Boolean,
        /** A watch send was stopped by the phone after the user last confirmed the setting. */
        val stoppedSinceAck: Boolean,
        /** The user already confirmed the manufacturer setting once. */
        val acknowledged: Boolean,
    ) {
        /**
         * Show the prompt when a problem is known (no battery exemption, or a send was cut
         * off since the user last confirmed), or on ColorOS until the user confirms once.
         */
        val shouldPrompt: Boolean
            get() = !batteryExempt || stoppedSinceAck || (colorOs && !acknowledged)
    }

    fun status(context: Context, storage: Storage): Status {
        val ackAt = storage.backgroundHelpAckAt
        return Status(
            batteryExempt = isBatteryExempt(context),
            colorOs = Build.MANUFACTURER.lowercase() in COLOROS_MANUFACTURERS,
            stoppedSinceAck = storage.watchPushStoppedBySystem && storage.watchPushAt > ackAt,
            acknowledged = ackAt > 0L,
        )
    }

    fun isBatteryExempt(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /**
     * Ask Android for the battery-optimisation exemption (a one-tap system dialog). The app
     * declares REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, which this intent requires.
     */
    fun requestBatteryExemption(context: Context) {
        if (isBatteryExempt(context)) return
        launch(
            context,
            Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}"),
            ),
        )
    }

    /**
     * The system "App info" page for [packageName]. On ColorOS, *Battery usage* on that page
     * holds "Allow background activity" - there is no intent that opens it directly.
     */
    fun openAppInfo(context: Context, packageName: String = context.packageName) {
        launch(
            context,
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
        )
    }

    fun isInstalled(context: Context, packageName: String): Boolean = try {
        context.packageManager.getPackageInfo(packageName, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun launch(context: Context, intent: Intent) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: ActivityNotFoundException) {
            // Some OEM builds strip a settings screen; fall back to nothing rather than crash.
            Log.w(TAG, "no activity for ${intent.action}: ${e.message}")
        }
    }
}
