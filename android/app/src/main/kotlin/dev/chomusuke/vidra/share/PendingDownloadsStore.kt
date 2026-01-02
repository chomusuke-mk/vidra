package dev.chomusuke.vidra.share

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.UUID

data class ManualDownloadOptions(
    val onlyAudio: Boolean,
    val resolution: String?,
    val videoFormat: String?,
    val audioFormat: String?,
    val audioLanguage: String?,
    val subtitles: String?,
) {
    fun toJson(): JSONObject {
        val json = JSONObject()
        json.put("onlyAudio", onlyAudio)
        json.put("resolution", resolution)
        json.put("videoFormat", videoFormat)
        json.put("audioFormat", audioFormat)
        json.put("audioLanguage", audioLanguage)
        json.put("subtitles", subtitles)
        return json
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "onlyAudio" to onlyAudio,
        "resolution" to resolution,
        "videoFormat" to videoFormat,
        "audioFormat" to audioFormat,
        "audioLanguage" to audioLanguage,
        "subtitles" to subtitles,
    )

    companion object {
        fun fromJson(json: JSONObject?): ManualDownloadOptions? {
            if (json == null) {
                return null
            }
            return ManualDownloadOptions(
                onlyAudio = json.optBoolean("onlyAudio", false),
                resolution = json.optString("resolution").takeIf { it.isNotEmpty() },
                videoFormat = json.optString("videoFormat").takeIf { it.isNotEmpty() },
                audioFormat = json.optString("audioFormat").takeIf { it.isNotEmpty() },
                audioLanguage = json.optString("audioLanguage").takeIf { it.isNotEmpty() },
                subtitles = json.optString("subtitles").takeIf { it.isNotEmpty() },
            )
        }
    }
}

data class PendingDownloadEntry(
    val id: String = UUID.randomUUID().toString(),
    val presetId: String,
    val payload: ShareIntentPayload,
    val options: ManualDownloadOptions?,
    val preferenceOverrides: Map<String, Any?>? = null,
    val addedAt: Long = System.currentTimeMillis(),
) {
    fun toJson(): JSONObject {
        val json = JSONObject()
        json.put("id", id)
        json.put("presetId", presetId)
        json.put("payload", payload.toJson())
        json.put("addedAt", addedAt)
        options?.let { json.put("options", it.toJson()) }
        preferenceOverrides?.let { overrides ->
            json.put("preferenceOverrides", mapToJson(overrides))
        }
        return json
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "presetId" to presetId,
        "payload" to payload.toMap(),
        "options" to options?.toMap(),
        "preferenceOverrides" to preferenceOverrides,
        "addedAt" to addedAt,
    )

    companion object {
        fun fromJson(json: JSONObject?): PendingDownloadEntry? {
            if (json == null) {
                return null
            }
            val payload = ShareIntentPayload.fromJson(json.optJSONObject("payload"))
                ?: return null
            val presetId = json.optString("presetId")
            if (presetId.isEmpty()) {
                return null
            }
            return PendingDownloadEntry(
                id = json.optString("id").takeIf { it.isNotEmpty() } ?: UUID.randomUUID().toString(),
                presetId = presetId,
                payload = payload,
                options = ManualDownloadOptions.fromJson(json.optJSONObject("options")),
                preferenceOverrides = json.optJSONObject("preferenceOverrides")?.let { jsonToMap(it) },
                addedAt = json.optLong("addedAt", System.currentTimeMillis()),
            )
        }
    }
}

private const val STORE_TAG = "PendingDownloadsStore"

object PendingDownloadsStore {
    private const val PREFS = "share_pending_downloads"
    private const val KEY_ENTRIES = "entries"

    fun enqueue(
        context: Context,
        payload: ShareIntentPayload,
        presetId: String,
        options: ManualDownloadOptions? = null,
        preferenceOverrides: Map<String, Any?>? = null,
    ) {
        val entry = PendingDownloadEntry(
            presetId = presetId,
            payload = payload,
            options = options,
            preferenceOverrides = preferenceOverrides,
        )
        Log.d(
            STORE_TAG,
            "enqueue preset=$presetId urls=${payload.urls.size} overrides=${preferenceOverrides?.keys} options=${options != null}",
        )
        val current = loadEntries(context).toMutableList()
        current.add(entry)
        persistEntries(context, current)
    }

    fun drain(context: Context): List<PendingDownloadEntry> {
        val entries = loadEntries(context)
        Log.d(STORE_TAG, "drain returning ${entries.size} entries")
        persistEntries(context, emptyList())
        return entries
    }

    private fun loadEntries(context: Context): List<PendingDownloadEntry> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_ENTRIES, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            val items = mutableListOf<PendingDownloadEntry>()
            for (index in 0 until array.length()) {
                val entry = PendingDownloadEntry.fromJson(array.optJSONObject(index))
                if (entry != null) {
                    items.add(entry)
                }
            }
            Log.d(STORE_TAG, "loadEntries parsed ${items.size} items")
            items
        } catch (_: JSONException) {
            Log.w(STORE_TAG, "Failed to parse pending downloads JSON payload")
            emptyList()
        }
    }

    private fun persistEntries(context: Context, entries: List<PendingDownloadEntry>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val array = JSONArray()
        entries.forEach { array.put(it.toJson()) }
        prefs.edit().putString(KEY_ENTRIES, array.toString()).apply()
    }

}

private fun mapToJson(values: Map<String, Any?>): JSONObject {
    val json = JSONObject()
    values.forEach { entry ->
        val key = entry.key
        val value = entry.value
        when (value) {
            null -> json.put(key, JSONObject.NULL)
            is Boolean, is Number, is String -> json.put(key, value)
            else -> json.put(key, value.toString())
        }
    }
    return json
}

private fun jsonToMap(json: JSONObject): Map<String, Any?> {
    val result = mutableMapOf<String, Any?>()
    val keys = json.keys()
    while (keys.hasNext()) {
        val key = keys.next()
        result[key] = json.opt(key)
    }
    return result
}
