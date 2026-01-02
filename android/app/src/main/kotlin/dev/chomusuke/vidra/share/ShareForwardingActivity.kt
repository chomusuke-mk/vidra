package dev.chomusuke.vidra.share

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import dev.chomusuke.vidra.MainActivity

/**
 * Lightweight activity that forwards the inbound share intent to [MainActivity]
 * while stamping the preset ID so Flutter can decide which workflow to run.
 */
abstract class ShareForwardingActivity : Activity() {
    /** Preset identifier understood by the Flutter share pipeline. */
    protected abstract val presetId: String?

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        forwardToMain()
    }

    private fun forwardToMain() {
        val incoming = intent
        val forwardIntent = if (incoming != null) Intent(incoming) else Intent()
        forwardIntent.setClass(this, MainActivity::class.java)
        forwardIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        forwardIntent.putExtra(MainActivity.EXTRA_SHARE_DIRECT, true)
        presetId?.let {
            forwardIntent.putExtra(MainActivity.EXTRA_SHARE_PRESET, it)
        }
        startActivity(forwardIntent)
        finish()
    }
}
