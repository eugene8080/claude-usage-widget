package com.usage.claudewidget.watch

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import com.usage.claudewidget.BuildConfig
import com.usage.claudewidget.data.UsageSnapshot
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume

/**
 * Pushes the usage snapshot to the Garmin watch app over BLE, via Garmin Connect Mobile.
 *
 * This is the only thing that ever reaches the watch. The watch app holds no credentials and
 * makes no web requests - see watch/README.md for why that is not negotiable - so if this
 * push does not happen, the glance shows nothing.
 *
 * Every failure here is swallowed and logged. A watch that is out of range, a Garmin Connect
 * Mobile that is not installed, a watch app that was never sideloaded: none of those are
 * reasons to fail a refresh whose real job is updating the home-screen widget.
 */
object WatchBridge {

    /** Must match `id` in watch/manifest.xml; the watch app is addressed by this, not by name. */
    private const val WATCH_APP_ID = "8a5bd20e02f34f58afb5f357a23a4a65"

    private const val TAG = "ClaudeWatch"

    /**
     * The whole handshake - initialize, enumerate devices, query app info, send - is
     * callback-driven with no overall timeout of its own. A watch that is paired but asleep
     * simply never calls back, so the coroutine needs its own deadline or a background
     * refresh would hang until WorkManager kills it.
     */
    private const val TIMEOUT_MS = 15_000L

    sealed interface PushResult {
        data class Sent(val deviceName: String) : PushResult
        /** Nothing to talk to: no paired watch, or the watch app is not installed. */
        data class NoTarget(val reason: String) : PushResult
        data class Failed(val reason: String) : PushResult
    }

    /**
     * Send [snapshot] to every connected watch that has the app installed.
     *
     * Returns rather than throws; the caller is expected to log and carry on.
     */
    suspend fun push(context: Context, snapshot: UsageSnapshot): PushResult =
        withContext(Dispatchers.IO) {
            // Must NOT be the main thread. The tethered strategy does its own blocking TCP
            // inside getConnectedDevices()/sendMessage() - it talks to the simulator over an
            // adb-forwarded socket - so driving this from the main looper throws
            // NetworkOnMainThreadException. The SDK delivers its callbacks on the main
            // looper either way, which is all it actually needs the main thread for.
            try {
                withTimeout(TIMEOUT_MS) { pushInternal(context, snapshot) }
            } catch (e: TimeoutCancellationException) {
                Log.w(TAG, "push timed out after ${TIMEOUT_MS}ms")
                PushResult.Failed("timeout")
            } catch (e: Exception) {
                // Includes InvalidStateException and ServiceUnavailableException, thrown when
                // Garmin Connect Mobile is missing or its service is not bound yet.
                Log.w(TAG, "push failed: ${e.javaClass.simpleName}: ${e.message}")
                PushResult.Failed(e.javaClass.simpleName)
            }
        }

    private suspend fun pushInternal(context: Context, snapshot: UsageSnapshot): PushResult {
        val connectType = if (BuildConfig.CIQ_TETHERED) {
            // Talks to the Connect IQ simulator over `adb forward tcp:7381 tcp:7381` instead
            // of to a real watch. Enabled only by a build flag, never at runtime, so a
            // shipped build cannot end up in this mode.
            ConnectIQ.IQConnectType.TETHERED
        } else {
            ConnectIQ.IQConnectType.WIRELESS
        }
        // getInstance and initialize both build Handlers, so they need a Looper thread;
        // everything after them does blocking socket work and must not be on one.
        val connectIQ = withContext(Dispatchers.Main) {
            ConnectIQ.getInstance(context, connectType)
        }

        if (!awaitSdkReady(context, connectIQ)) {
            return PushResult.NoTarget("sdk-not-ready")
        }

        val devices: List<IQDevice> = connectIQ.connectedDevices.orEmpty()
        if (devices.isEmpty()) {
            return PushResult.NoTarget("no-connected-device")
        }

        val payload = payloadOf(snapshot)
        var lastResult: PushResult = PushResult.NoTarget("app-not-installed")

        for (device in devices) {
            // getApplicationInfo is what reports whether our app is sideloaded on THIS watch.
            // Sending to a device without it silently goes nowhere, so ask first.
            val app = awaitApplicationInfo(connectIQ, device) ?: continue
            lastResult = awaitSend(connectIQ, device, app, payload)
            if (lastResult is PushResult.Sent) {
                Log.i(TAG, "pushed to ${device.friendlyName}")
            } else {
                Log.w(TAG, "push to ${device.friendlyName} -> $lastResult")
            }
        }
        return lastResult
    }

    /**
     * The payload the watch's Snapshot.store() expects. Keys are terse because a Connect IQ
     * message is small and this crosses a BLE link; they are mirrored verbatim in
     * watch/source/Snapshot.mc.
     *
     * Percentages are rounded to whole numbers here rather than on the watch: the watch
     * renders what it is given, and this keeps the phone as the single place that decides
     * how a figure is presented.
     */
    private fun payloadOf(snapshot: UsageSnapshot): Map<String, Any> {
        val payload = mutableMapOf<String, Any>(
            "fh" to snapshot.fiveHour.utilization.toSafeInt(),
            "fhr" to snapshot.fiveHour.resetsAtEpochMs.toEpochSeconds(),
            "wk" to snapshot.sevenDay.utilization.toSafeInt(),
            "wkr" to snapshot.sevenDay.resetsAtEpochMs.toEpochSeconds(),
            // Epoch SECONDS: Monkey C's Number is 32-bit, so epoch milliseconds would
            // overflow it. Time.now().value() on the watch is seconds too.
            "ts" to snapshot.fetchedAtEpochMs.toEpochSeconds(),
        )
        val model = snapshot.modelWeekly
        if (model != null) {
            payload["mw"] = model.window.utilization.toSafeInt()
            payload["mwr"] = model.window.resetsAtEpochMs.toEpochSeconds()
            payload["mwn"] = model.modelName
        }
        // When there is no per-model cap the keys are omitted entirely; the watch treats a
        // payload without them as "clear that meter" rather than "leave the last value".
        return payload
    }

    private fun Float.toSafeInt(): Int = this.coerceIn(0f, 100f).toInt()

    private fun Long.toEpochSeconds(): Int = (this / 1000L).toInt()

    // ---- callback bridging -------------------------------------------------------------
    //
    // Each SDK callback can in principle fire more than once (onSdkReady after a reconnect,
    // for example). A continuation may only be resumed once, so each wrapper below guards
    // with an AtomicBoolean rather than trusting the SDK to call back exactly once.

    private suspend fun awaitSdkReady(context: Context, connectIQ: ConnectIQ): Boolean =
        suspendCancellableCoroutine { cont ->
            val done = AtomicBoolean(false)
            val listener = object : ConnectIQ.ConnectIQListener {
                override fun onSdkReady() = cont.resumeOnce(done, true)

                override fun onInitializeError(status: ConnectIQ.IQSdkErrorStatus) {
                    Log.w(TAG, "SDK init error: $status")
                    cont.resumeOnce(done, false)
                }

                override fun onSdkShutDown() {
                    // Only interesting if it happens before we ever became ready.
                    cont.resumeOnce(done, false)
                }
            }
            // connectToGCM = false: the `true` variant can put up a dialog prompting the user
            // to install Garmin Connect Mobile, and this runs from a background Worker where
            // there is no Activity to host one.
            //
            // Posted to the main looper because initialize() constructs a Handler and throws
            // "Can't create handler inside thread ... that has not called Looper.prepare()"
            // on a plain worker thread. The callbacks then arrive on the main looper and
            // resume this coroutine back onto its own dispatcher.
            Handler(Looper.getMainLooper()).post {
                connectIQ.initialize(context, false, listener)
            }
        }

    private suspend fun awaitApplicationInfo(connectIQ: ConnectIQ, device: IQDevice): IQApp? =
        suspendCancellableCoroutine { cont ->
            val done = AtomicBoolean(false)
            connectIQ.getApplicationInfo(
                WATCH_APP_ID,
                device,
                object : ConnectIQ.IQApplicationInfoListener {
                    override fun onApplicationInfoReceived(app: IQApp) =
                        cont.resumeOnce(done, app)

                    override fun onApplicationNotInstalled(applicationId: String) {
                        Log.i(TAG, "watch app not installed on ${device.friendlyName}")
                        cont.resumeOnce(done, null)
                    }
                },
            )
        }

    private suspend fun awaitSend(
        connectIQ: ConnectIQ,
        device: IQDevice,
        app: IQApp,
        payload: Map<String, Any>,
    ): PushResult = suspendCancellableCoroutine { cont ->
        val done = AtomicBoolean(false)
        connectIQ.sendMessage(device, app, payload) { _, _, status ->
            if (status == ConnectIQ.IQMessageStatus.SUCCESS) {
                cont.resumeOnce(done, PushResult.Sent(device.friendlyName))
            } else {
                cont.resumeOnce(done, PushResult.Failed(status.name))
            }
        }
    }

    private fun <T> CancellableContinuation<T>.resumeOnce(guard: AtomicBoolean, value: T) {
        if (guard.compareAndSet(false, true) && isActive) {
            resume(value)
        }
    }
}
