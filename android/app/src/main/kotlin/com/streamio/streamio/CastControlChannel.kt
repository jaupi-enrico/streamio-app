package com.streamio.streamio

import com.google.android.gms.cast.Cast
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * The `urn:x-cast:com.streamio.control` channel, for lib/core/cast/cast_control_channel.dart.
 *
 * This exists because **flutter_chrome_cast has no custom-namespace API at
 * all** — not in Dart, not in its Kotlin, not in its Swift. Everything else
 * the cast panel needs (play/pause, relative seek, active track ids, media
 * status) the plugin does expose and is used from Dart; only the Streamio
 * control protocol has to come down here. See `docs/protocol.md` in the
 * `cast-receiver` repo for what travels over it.
 *
 * Two things this must get right:
 *
 *  * **Re-attach on every session.** A message callback is registered against
 *    a [CastSession], not against the SessionManager, so it dies with the
 *    session. A cast resumed from the notification — or from another sender —
 *    would otherwise leave the panel connected to nothing, which looks exactly
 *    like a receiver that stopped answering.
 *  * **Never throw at Dart.** Every message is advisory on both sides (the
 *    device may be running a receiver older than this build). No session, no
 *    channel, a send that fails: all no-ops. A cast that plays must not be
 *    breakable by a control that isn't there.
 */
class CastControlChannel(context: Context, messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "StreamioCast"
        private const val NAMESPACE = "urn:x-cast:com.streamio.control"

        /** One second apart, for a minute: the SDK comes up in a few of these. */
        private const val RETRY_MS = 1000L
        private const val MAX_ATTEMPTS = 60
        private const val METHOD_CHANNEL = "streamio/cast_control"
        private const val EVENT_CHANNEL = "streamio/cast_control/events"
    }

    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null

    /** The session the callback is currently attached to, so it is removed once. */
    private var attached: CastSession? = null

    /** Whether [sessionListener] is registered, so it is never added twice. */
    private var listening = false

    /** Attach attempts spent waiting for the Cast SDK to come up. */
    private var attempts = 0

    private val retry = Runnable { listen() }

    /** Messages already retried once, so a failing one can't loop forever. */
    private val retried = mutableSetOf<String>()

    /** First message only: enough to tell "the receiver answers" from "it doesn't". */
    private var loggedFirstMessage = false

    private val onMessage = Cast.MessageReceivedCallback { _, _, message ->
        if (!loggedFirstMessage) {
            loggedFirstMessage = true
            Log.i(TAG, "first message on $NAMESPACE (${message.length} bytes)")
        }
        // Hop to the main thread: the Cast SDK may deliver off it, and an
        // EventSink is only safe to touch from the platform thread.
        main.post { events?.success(message) }
    }

    private val sessionListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) = attach(session)
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) = attach(session)
        override fun onSessionEnded(session: CastSession, error: Int) = detach()
        override fun onSessionSuspended(session: CastSession, reason: Int) = detach()

        override fun onSessionStarting(session: CastSession) = Unit
        override fun onSessionResuming(session: CastSession, sessionId: String) = Unit
        override fun onSessionEnding(session: CastSession) = Unit
        override fun onSessionStartFailed(session: CastSession, error: Int) = Unit
        override fun onSessionResumeFailed(session: CastSession, error: Int) = Unit
    }

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "send" -> {
                    send(call.arguments as? String)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                    listen()
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                    stopListening()
                }
            }
        )
    }

    /**
     * [CastContext.getSharedInstance] throws when Google Play services are
     * missing or too old, which is the same condition that already hides the
     * Cast button. Treated as "no cast here" rather than as an error.
     */
    private fun castContext(): CastContext? = try {
        CastContext.getSharedInstance(appContext)
    } catch (err: Exception) {
        null
    }

    /**
     * **This retries, and that is the whole point.**
     *
     * [CastContext.getSharedInstance] throws until the Cast SDK has been
     * initialized, and the app initializes it from Dart — `CastService.initialize`
     * resolves the receiver id (a `/api/cast-config` round trip) before calling
     * `setSharedInstanceWithOptions`. The Flutter side subscribes to this
     * channel as soon as anything watches `castStateProvider`, which is well
     * before that lands. This used to be a one-shot: no context at that
     * instant meant the session listener was never registered and **no `STATE`
     * ever arrived for the rest of the process** — silently, since every
     * message here is advisory. The panel then had transport controls and
     * nothing else: no title, no duration, no subtitle or audio or episode
     * picker, which is exactly what it looked like on a real device.
     */
    private fun listen() {
        main.removeCallbacks(retry)
        val manager = castContext()?.sessionManager
        if (manager == null) {
            if (events == null) return
            if (attempts++ < MAX_ATTEMPTS) {
                main.postDelayed(retry, RETRY_MS)
            } else {
                // Play services missing, or the OPTIONS_PROVIDER meta-data
                // absent from the manifest — the same condition that hides the
                // Cast button. Not going to fix itself.
                Log.w(TAG, "no CastContext after ${MAX_ATTEMPTS}s; giving up")
            }
            return
        }

        attempts = 0
        if (!listening) {
            manager.addSessionManagerListener(sessionListener, CastSession::class.java)
            listening = true
            Log.i(TAG, "listening for cast sessions")
        }
        // A session may already be running — the app can be reopened onto one,
        // and by the time the SDK is up the session usually already exists.
        manager.currentCastSession?.let { attach(it) }
    }

    private fun stopListening() {
        main.removeCallbacks(retry)
        attempts = 0
        detach()
        if (!listening) return
        listening = false
        castContext()?.sessionManager
            ?.removeSessionManagerListener(sessionListener, CastSession::class.java)
    }

    private fun attach(session: CastSession) {
        if (attached === session) return
        detach()
        try {
            session.setMessageReceivedCallbacks(NAMESPACE, onMessage)
            attached = session
            Log.i(TAG, "attached to ${session.castDevice?.friendlyName ?: "session"}")
        } catch (err: Exception) {
            // The session went away between the callback and here.
            Log.w(TAG, "could not attach to the session: $err")
        }
    }

    private fun detach() {
        val session = attached ?: return
        attached = null
        try {
            session.removeMessageReceivedCallbacks(NAMESPACE)
        } catch (err: Exception) {
            // Already gone; nothing to remove.
        }
    }

    private fun send(json: String?) {
        if (json == null) return
        val session = castContext()?.sessionManager?.currentCastSession
        if (session == null) {
            // Ordinary: the sender says HELLO the moment something starts
            // watching for STATE, which is usually before a session exists.
            // The receiver broadcasts on its own anyway, and Dart re-sends the
            // HELLO once a session is up.
            Log.i(TAG, "dropping a control message: no session yet")
            if (!listening) listen()
            return
        }
        try {
            session.sendMessage(NAMESPACE, json).setResultCallback { status ->
                if (status.isSuccess) return@setResultCallback
                // The first HELLO routinely races the session's own handshake
                // and comes back as a transport error. One retry covers that;
                // beyond it the message is advisory and gets dropped, as
                // everything on this channel is allowed to be.
                if (retried.add(json)) {
                    Log.i(TAG, "send failed (${status.statusCode}), retrying once")
                    main.postDelayed({ send(json) }, RETRY_MS)
                } else {
                    Log.w(TAG, "send failed (${status.statusCode}): $json")
                }
            }
        } catch (err: Exception) {
            // Disconnected mid-send. The sender treats every message as
            // advisory, so dropping it is the correct outcome.
        }
    }
}
