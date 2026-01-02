package dev.chomusuke.vidra.share

import android.content.Context
import android.content.SharedPreferences

/**
 * Lightweight key-value store for remembering manual overlay selections between sessions.
 */
object ManualOverlayPreferenceStore {
    private const val PREFS_NAME = "manual_overlay_preferences"
    private const val KEY_PREFIX = "overlay_"

    private fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun readString(context: Context, key: String, default: String? = null): String? {
        return prefs(context).getString(namespaced(key), default)
    }

    fun readBoolean(context: Context, key: String, default: Boolean = false): Boolean {
        return prefs(context).getBoolean(namespaced(key), default)
    }

    fun writeString(context: Context, key: String, value: String?) {
        prefs(context).edit().putString(namespaced(key), value).apply()
    }

    fun writeBoolean(context: Context, key: String, value: Boolean) {
        prefs(context).edit().putBoolean(namespaced(key), value).apply()
    }

    private fun namespaced(key: String): String = KEY_PREFIX + key
}
