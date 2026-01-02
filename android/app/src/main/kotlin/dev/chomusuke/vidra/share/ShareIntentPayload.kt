package dev.chomusuke.vidra.share

/**
 * Normalized representation of the data extracted from an Android share intent.
 */
data class ShareIntentPayload(
    val rawText: String,
    val urls: List<String>,
    val displayName: String?,
    val presetId: String?,
    val directShare: Boolean,
    val sourcePackage: String?,
    val subject: String?,
    val timestamp: Long = System.currentTimeMillis(),
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "rawText" to rawText,
            "urls" to ArrayList(urls),
            "displayName" to displayName,
            "presetId" to presetId,
            "directShare" to directShare,
            "sourcePackage" to sourcePackage,
            "subject" to subject,
            "timestamp" to timestamp,
        )
    }

    fun toJsonString(): String {
        return toJson().toString()
    }

    fun toJson(): org.json.JSONObject {
        val json = org.json.JSONObject()
        json.put("rawText", rawText)
        json.put("displayName", displayName)
        json.put("presetId", presetId)
        json.put("directShare", directShare)
        json.put("sourcePackage", sourcePackage)
        json.put("subject", subject)
        json.put("timestamp", timestamp)
        val urlsArray = org.json.JSONArray()
        urls.forEach { urlsArray.put(it) }
        json.put("urls", urlsArray)
        return json
    }

    companion object {
        fun fromJsonString(value: String?): ShareIntentPayload? {
            if (value.isNullOrBlank()) {
                return null
            }
            return try {
                val json = org.json.JSONObject(value)
                fromJson(json)
            } catch (_: org.json.JSONException) {
                null
            }
        }

        fun fromJson(json: org.json.JSONObject?): ShareIntentPayload? {
            if (json == null) {
                return null
            }
            val urlsArray = json.optJSONArray("urls") ?: org.json.JSONArray()
            val urls = mutableListOf<String>()
            for (index in 0 until urlsArray.length()) {
                val value = urlsArray.optString(index)
                if (!value.isNullOrEmpty()) {
                    urls.add(value)
                }
            }
            if (urls.isEmpty() && json.optString("rawText").isNullOrEmpty()) {
                return null
            }
            return ShareIntentPayload(
                rawText = json.optString("rawText"),
                urls = urls,
                displayName = json.optString("displayName").takeIf { it.isNotEmpty() },
                presetId = json.optString("presetId").takeIf { it.isNotEmpty() },
                directShare = json.optBoolean("directShare", false),
                sourcePackage = json.optString("sourcePackage").takeIf { it.isNotEmpty() },
                subject = json.optString("subject").takeIf { it.isNotEmpty() },
                timestamp = json.optLong("timestamp", System.currentTimeMillis()),
            )
        }
    }
}
