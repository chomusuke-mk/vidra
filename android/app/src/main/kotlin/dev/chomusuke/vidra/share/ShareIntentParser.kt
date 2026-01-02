package dev.chomusuke.vidra.share

import android.content.ClipData
import android.content.Intent
import android.util.Patterns
import kotlin.math.min

object ShareIntentParser {
    fun parse(
        intent: Intent?,
        presetExtraKey: String,
        directShareExtraKey: String,
    ): ShareIntentPayload? {
        if (intent == null) {
            return null
        }
        val action = intent.action ?: return null
        val supportedAction = action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE
        if (!supportedAction) {
            return null
        }
        val type = intent.type ?: ""
        if (!type.startsWith("text/")) {
            return null
        }
        val sharedText = extractSharedText(intent)?.trim() ?: return null
        if (sharedText.isEmpty()) {
            return null
        }
        val normalizedText = sharedText.replace('\r', '\n').trim()
        if (normalizedText.isEmpty()) {
            return null
        }
        val lines = normalizedText
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        if (lines.isEmpty()) {
            return null
        }
        val firstLine = lines.first()
        val presetId = intent.getStringExtra(presetExtraKey)
        val directShareFlag = intent.getBooleanExtra(directShareExtraKey, false)
        val firstIsUrl = isLikelyUrl(firstLine)
        val candidateLines = if (firstIsUrl) lines else lines.drop(1)
        val urls = extractUrls(candidateLines.ifEmpty { lines })
        val displayName = when {
            !firstIsUrl && lines.size > 1 -> firstLine
            !firstIsUrl && urls.isEmpty() -> firstLine
            else -> null
        }
        val resolvedUrls = when {
            urls.isNotEmpty() -> urls
            isLikelyUrl(normalizedText) -> listOf(normalizedText)
            else -> emptyList()
        }
        if (resolvedUrls.isEmpty()) {
            return null
        }
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val sourcePackage = intent.`package`
            ?: intent.getStringExtra(Intent.EXTRA_REFERRER_NAME)
        return ShareIntentPayload(
            rawText = normalizedText,
            urls = resolvedUrls,
            displayName = displayName,
            presetId = presetId,
            directShare = directShareFlag || presetId != null,
            sourcePackage = sourcePackage,
            subject = subject,
        )
    }

    private fun extractSharedText(intent: Intent): String? {
        intent.getStringExtra(Intent.EXTRA_TEXT)?.let { extra ->
            if (extra.isNotBlank()) {
                return extra
            }
        }
        val clipData = intent.clipData ?: return null
        consumeClipDataText(clipData)?.let { return it }
        return null
    }

    private fun consumeClipDataText(clipData: ClipData): String? {
        for (index in 0 until clipData.itemCount) {
            val item = clipData.getItemAt(index) ?: continue
            val textValue = item.text?.toString()
            if (!textValue.isNullOrBlank()) {
                return textValue
            }
            val uri = item.uri
            if (uri != null) {
                val candidate = uri.toString()
                if (candidate.isNotBlank()) {
                    return candidate
                }
            }
        }
        return null
    }

    private fun extractUrls(lines: List<String>): List<String> {
        if (lines.isEmpty()) {
            return emptyList()
        }
        val urls = LinkedHashSet<String>()
        for (line in lines) {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) {
                continue
            }
            val matcher = Patterns.WEB_URL.matcher(trimmed)
            var foundInLine = false
            while (matcher.find()) {
                val start = matcher.start()
                val end = matcher.end()
                if (start < 0 || end <= start) {
                    continue
                }
                val candidate = trimmed.substring(start, min(end, trimmed.length)).trim()
                if (candidate.isNotEmpty()) {
                    urls.add(candidate)
                    foundInLine = true
                }
            }
            if (!foundInLine && isLikelyUrl(trimmed)) {
                urls.add(trimmed)
            }
        }
        return urls.toList()
    }

    private fun isLikelyUrl(value: String?): Boolean {
        if (value.isNullOrBlank()) {
            return false
        }
        val text = value.trim()
        if (text.contains(' ')) {
            return false
        }
        if (text.startsWith("http://") || text.startsWith("https://")) {
            return true
        }
        if (text.contains(".")) {
            return Patterns.WEB_URL.matcher(text).matches()
        }
        return false
    }
}
