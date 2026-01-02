package dev.chomusuke.vidra

import android.content.Intent
import android.os.Bundle
import android.util.Log
import dev.chomusuke.vidra.share.PendingDownloadsStore
import dev.chomusuke.vidra.share.ShareIntentParser
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NATIVE = "dev.chomusuke.vidra/native"
        private const val CHANNEL_SHARE_EVENTS = "dev.chomusuke.vidra/share/events"
        const val EXTRA_SHARE_PRESET = "dev.chomusuke.vidra.EXTRA_SHARE_PRESET"
        const val EXTRA_SHARE_DIRECT = "dev.chomusuke.vidra.EXTRA_SHARE_DIRECT"
        private const val EXTRA_SHARE_CONSUMED = "dev.chomusuke.vidra.EXTRA_SHARE_CONSUMED"
        private const val TAG = "MainActivity"
    }

    private var shareEventSink: EventChannel.EventSink? = null
    private val pendingSharePayloads = mutableListOf<Map<String, Any?>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NATIVE)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeLibDir" -> result.success(applicationInfo.nativeLibraryDir)
                    "drainPendingDownloads" -> {
                        val entries = PendingDownloadsStore.drain(applicationContext)
                        val payload = entries.map { it.toMap() }
                        result.success(payload)
                    }
                    "returnToPreviousApp" -> {
                        runOnUiThread {
                            Log.d(TAG, "returnToPreviousApp requested via channel")
                            val moved = moveTaskToBack(true)
                            Log.d(TAG, "returnToPreviousApp moveTaskToBack result=$moved")
                            result.success(moved)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SHARE_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    shareEventSink = events
                    flushPendingSharePayloads()
                }

                override fun onCancel(arguments: Any?) {
                    shareEventSink = null
                }
            })
    }

    private fun handleShareIntent(intent: Intent?) {
        Log.d(TAG, "handleShareIntent called with intent=$intent")
        if (intent == null) {
            Log.d(TAG, "No intent provided")
            return
        }
        if (intent.getBooleanExtra(EXTRA_SHARE_CONSUMED, false)) {
            Log.d(TAG, "Intent already consumed")
            return
        }
        val payload = ShareIntentParser.parse(intent, EXTRA_SHARE_PRESET, EXTRA_SHARE_DIRECT)
            ?: return
        Log.d(TAG, "Parsed share payload with ${payload.urls.size} urls, preset=${payload.presetId}")
        intent.putExtra(EXTRA_SHARE_CONSUMED, true)
        emitSharePayload(payload.toMap())
    }

    private fun emitSharePayload(payload: Map<String, Any?>) {
        val sink = shareEventSink
        if (sink != null) {
            Log.d(TAG, "Emitting share payload to Flutter listeners")
            sink.success(payload)
            return
        }
        Log.d(TAG, "Share sink not ready, queueing payload")
        pendingSharePayloads.add(payload)
    }

    private fun flushPendingSharePayloads() {
        val sink = shareEventSink ?: return
        if (pendingSharePayloads.isEmpty()) {
            return
        }
        Log.d(TAG, "Flushing ${pendingSharePayloads.size} queued share payloads")
        val iterator = pendingSharePayloads.iterator()
        while (iterator.hasNext()) {
            sink.success(iterator.next())
            iterator.remove()
        }
    }
}