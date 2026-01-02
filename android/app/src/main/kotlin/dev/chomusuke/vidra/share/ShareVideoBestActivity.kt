package dev.chomusuke.vidra.share

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import dev.chomusuke.vidra.MainActivity
import dev.chomusuke.vidra.R

class ShareVideoBestActivity : Activity() {
    companion object {
        private const val TAG = "ShareVideoBestActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate - received share intent: $intent")
        handleShare()
    }

    private fun handleShare() {
        Log.d(TAG, "handleShare invoked")
        val payload = ShareIntentParser.parse(
            intent,
            MainActivity.EXTRA_SHARE_PRESET,
            MainActivity.EXTRA_SHARE_DIRECT,
        )?.copy(
            presetId = SharePresetIds.VIDEO_BEST,
            directShare = true,
        )
        if (payload == null || payload.urls.isEmpty()) {
            Log.w(TAG, "Failed to parse payload or no URLs present")
            Toast.makeText(this, R.string.share_pending_error, Toast.LENGTH_LONG).show()
            finish()
            return
        }
        Log.d(
            TAG,
            "Parsed payload with ${payload.urls.size} urls, preset=${payload.presetId}, directShare=${payload.directShare}",
        )
        PendingDownloadsStore.enqueue(
            context = this,
            payload = payload,
            presetId = SharePresetIds.VIDEO_BEST,
            preferenceOverrides = mapOf("playlist" to false),
        )
        Log.d(TAG, "Pending download enqueued, launching Vidra main activity")
        launchVidraApp(payload)
        Toast.makeText(this, R.string.share_pending_video_best, Toast.LENGTH_SHORT).show()
        finish()
    }

    private fun launchVidraApp(payload: ShareIntentPayload) {
        val shareText = resolveShareText(payload)
        val launchIntent = Intent(Intent.ACTION_SEND).apply {
            setClass(this@ShareVideoBestActivity, MainActivity::class.java)
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, shareText)
            if (!payload.subject.isNullOrBlank()) {
                putExtra(Intent.EXTRA_SUBJECT, payload.subject)
            }
            putExtra(MainActivity.EXTRA_SHARE_PRESET, SharePresetIds.VIDEO_BEST)
            putExtra(MainActivity.EXTRA_SHARE_DIRECT, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        Log.d(TAG, "Starting MainActivity with ACTION_SEND to trigger preset download")
        startActivity(launchIntent)
    }

    private fun resolveShareText(payload: ShareIntentPayload): String {
        if (payload.rawText.isNotBlank()) {
            return payload.rawText
        }
        return payload.urls.joinToString(separator = "\n")
    }
}
