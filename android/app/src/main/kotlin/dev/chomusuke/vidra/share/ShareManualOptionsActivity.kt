package dev.chomusuke.vidra.share

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import dev.chomusuke.vidra.MainActivity
import dev.chomusuke.vidra.R

class ShareManualOptionsActivity : Activity() {

    private val requestOverlayPermission = 4211
    private var pendingPayload: ShareIntentPayload? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preparePayload()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == requestOverlayPermission) {
            if (Settings.canDrawOverlays(this)) {
                launchOverlay()
            } else {
                Toast.makeText(this, R.string.share_overlay_permission_denied, Toast.LENGTH_LONG).show()
                finish()
            }
        }
    }

    private fun preparePayload() {
        val payload = ShareIntentParser.parse(
            intent,
            MainActivity.EXTRA_SHARE_PRESET,
            MainActivity.EXTRA_SHARE_DIRECT,
        )?.copy(
            presetId = SharePresetIds.MANUAL,
            directShare = true,
        )
        if (payload == null || payload.urls.isEmpty()) {
            Toast.makeText(this, R.string.share_pending_error, Toast.LENGTH_LONG).show()
            finish()
            return
        }
        pendingPayload = payload
        if (Settings.canDrawOverlays(this)) {
            launchOverlay()
        } else {
            Toast.makeText(this, R.string.share_overlay_permission_required, Toast.LENGTH_LONG).show()
            val permissionIntent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            startActivityForResult(permissionIntent, requestOverlayPermission)
        }
    }

    private fun launchOverlay() {
        val payload = pendingPayload
        if (payload == null) {
            Toast.makeText(this, R.string.share_overlay_invalid_payload, Toast.LENGTH_LONG).show()
            finish()
            return
        }
        val overlayIntent = Intent(this, ManualOptionsOverlayService::class.java).apply {
            putExtra(ManualOptionsOverlayService.EXTRA_PAYLOAD, payload.toJsonString())
        }
        startService(overlayIntent)
        finish()
    }
}
