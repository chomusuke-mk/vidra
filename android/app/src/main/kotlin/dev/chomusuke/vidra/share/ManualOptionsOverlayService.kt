package dev.chomusuke.vidra.share

import android.app.Service
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.text.Editable
import android.text.TextWatcher
import android.util.Log
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.BaseAdapter
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import androidx.core.graphics.ColorUtils
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.shape.CornerFamily
import com.google.android.material.switchmaterial.SwitchMaterial
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import dev.chomusuke.vidra.MainActivity
import dev.chomusuke.vidra.R
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

class ManualOptionsOverlayService : Service() {
    companion object {
        const val EXTRA_PAYLOAD = "dev.chomusuke.vidra.EXTRA_MANUAL_PAYLOAD"
        private const val TAG = "ManualOptionsOverlay"
        private const val PREF_ONLY_AUDIO = "only_audio"
        private const val PREF_RESOLUTION = "resolution"
        private const val PREF_VIDEO_FORMAT = "video_format"
        private const val PREF_AUDIO_FORMAT = "audio_format"
        private const val PREF_AUDIO_LANGUAGE = "audio_language"
        private const val PREF_SUBTITLES = "subtitles"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private val overlayThemeContext by lazy { ContextThemeWrapper(this, R.style.OverlayTheme) }
    private var payload: ShareIntentPayload? = null
    private lateinit var palette: FlutterThemePalette.Palette

    private var onlyAudioSelected = false
    private var resolutionSelection: String? = "best"
    private var formatSelection: String? = "mkv"
    private var audioFormatSelection: String? = "best"
    private var audioLanguageSelection: String? = "best"
    private var subtitlesSelection: String? = "none"

    private lateinit var resolutionRow: PreferenceRow
    private lateinit var formatRow: PreferenceRow
    private lateinit var audioFormatRow: PreferenceRow
    private lateinit var audioLanguageRow: PreferenceRow
    private lateinit var subtitlesRow: PreferenceRow
    private lateinit var onlyAudioIcon: ImageView
    private lateinit var onlyAudioTitle: TextView
    private lateinit var onlyAudioDesc: TextView
    private lateinit var videoOptionsContainer: View
    private lateinit var audioOnlyOptionsContainer: View

    private val languageEntries by lazy { buildLanguageEntries() }
    private val localizedLanguageOptions by lazy { buildLocalizedLanguageOptions(languageEntries) }
    private val languageLabelMap by lazy {
        languageEntries.associate { entry ->
            entry.code.lowercase(Locale.US) to entry.displayName
        }
    }

    private data class PreferenceOption(
        val value: String?,
        val label: String,
        val isCustom: Boolean = false,
    )

    private data class PreferenceRow(
        val card: MaterialCardView,
        val iconCard: MaterialCardView,
        val icon: ImageView,
        val title: TextView,
        val value: TextView,
        val chevron: ImageView,
    )

    private data class LanguageEntry(
        val code: String,
        val displayName: String,
    )

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        loadPersistedSelections()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val payloadJson = intent?.getStringExtra(EXTRA_PAYLOAD)
        val parsedPayload = ShareIntentPayload.fromJsonString(payloadJson)
        if (parsedPayload == null) {
            Toast.makeText(this, R.string.share_overlay_invalid_payload, Toast.LENGTH_LONG).show()
            stopSelf()
            return START_NOT_STICKY
        }
        Log.d(TAG, "Overlay invoked with intent=$intent and urls=${parsedPayload.urls.size}")
        payload = parsedPayload
        if (overlayView == null) {
            showOverlay()
        }
        return START_NOT_STICKY
    }

    private fun showOverlay() {
        val targetPayload = payload ?: return
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val inflater = LayoutInflater.from(overlayThemeContext)
        val view = inflater.inflate(R.layout.overlay_manual_options, null)
        overlayView = view
        palette = FlutterThemePalette.resolve(this)

        val paramsType = overlayWindowType()
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            paramsType,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM
            dimAmount = 0.35f
            flags = flags or WindowManager.LayoutParams.FLAG_DIM_BEHIND
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }

        val closeButton = view.findViewById<ImageButton>(R.id.overlay_close)
        val cancelButton = view.findViewById<MaterialButton>(R.id.overlay_cancel)
        val confirmButton = view.findViewById<MaterialButton>(R.id.overlay_confirm)
        val titleView = view.findViewById<TextView>(R.id.overlay_title)
        val subtitleView = view.findViewById<TextView>(R.id.overlay_subtitle)
        val sheetCard = view.findViewById<MaterialCardView>(R.id.overlay_sheet)
        val scrimView = view.findViewById<View>(R.id.overlay_scrim)
        val headerView = view.findViewById<View>(R.id.overlay_header)
        val onlyAudioCard = view.findViewById<MaterialCardView>(R.id.pref_card_only_audio)
        val onlyAudioIconCard = view.findViewById<MaterialCardView>(R.id.icon_card_only_audio)
        onlyAudioIcon = view.findViewById(R.id.icon_only_audio)
        val onlyAudioSwitch = view.findViewById<SwitchMaterial>(R.id.only_audio_switch)
        onlyAudioTitle = view.findViewById(R.id.pref_title_only_audio)
        onlyAudioDesc = view.findViewById(R.id.pref_desc_only_audio)
        videoOptionsContainer = view.findViewById(R.id.video_options_container)
        audioOnlyOptionsContainer = view.findViewById(R.id.audio_only_options_container)

        styleSheet(sheetCard, titleView, subtitleView)
        subtitleView.text = targetPayload.urls.firstOrNull()
            ?: targetPayload.displayName
            ?: targetPayload.subject
            ?: targetPayload.rawText.take(80)

        stylePreferenceCard(onlyAudioCard, onlyAudioIconCard, onlyAudioIcon)
        onlyAudioTitle.setTextColor(palette.onSurface)
        onlyAudioDesc.setTextColor(palette.onSurfaceVariant)
        styleSwitch(onlyAudioSwitch)
        onlyAudioSwitch.isChecked = onlyAudioSelected
        onlyAudioSwitch.setOnCheckedChangeListener { _, isChecked ->
            onlyAudioSelected = isChecked
            updateOnlyAudioMode()
            persistOverlayDefaults()
        }
        onlyAudioCard.setOnClickListener { onlyAudioSwitch.toggle() }

        resolutionRow = bindPreferenceRow(
            parent = view.findViewById(R.id.pref_card_resolution),
            iconRes = R.drawable.ic_pref_resolution,
            titleRes = R.string.share_pref_title_resolution,
        )
        formatRow = bindPreferenceRow(
            parent = view.findViewById(R.id.pref_card_format),
            iconRes = R.drawable.ic_pref_format,
            titleRes = R.string.share_pref_title_format,
        )
        audioFormatRow = bindPreferenceRow(
            parent = view.findViewById(R.id.pref_card_audio_format),
            iconRes = R.drawable.ic_pref_audio_only,
            titleRes = R.string.share_pref_title_audio_format,
        )
        audioLanguageRow = bindPreferenceRow(
            parent = view.findViewById(R.id.pref_card_audio_language),
            iconRes = R.drawable.ic_pref_language,
            titleRes = R.string.share_pref_title_audio_language,
        )
        subtitlesRow = bindPreferenceRow(
            parent = view.findViewById(R.id.pref_card_subtitles),
            iconRes = R.drawable.ic_pref_subtitles,
            titleRes = R.string.share_pref_title_subtitles,
        )

        resolutionRow.card.setOnClickListener {
            showChoiceDialog(
                titleRes = R.string.share_pref_dialog_resolution,
                options = buildResolutionOptions(),
                currentValue = resolutionSelection,
            ) { selection ->
                resolutionSelection = selection
                updateResolutionSummary()
                persistOverlayDefaults()
            }
        }
        formatRow.card.setOnClickListener {
            showChoiceDialog(
                titleRes = R.string.share_pref_dialog_format,
                options = buildFormatOptions(),
                currentValue = formatSelection,
            ) { selection ->
                formatSelection = selection
                updateFormatSummary()
                persistOverlayDefaults()
            }
        }
        audioFormatRow.card.setOnClickListener {
            showChoiceDialog(
                titleRes = R.string.share_pref_dialog_audio_format,
                options = buildAudioFormatOptions(),
                currentValue = audioFormatSelection,
            ) { selection ->
                audioFormatSelection = selection
                updateAudioFormatSummary()
                persistOverlayDefaults()
            }
        }
        audioLanguageRow.card.setOnClickListener {
            showLanguageSearchDialog(
                titleRes = R.string.share_pref_dialog_audio_language,
                options = buildAudioLanguageOptions(),
                currentValue = audioLanguageSelection,
            ) { selection ->
                audioLanguageSelection = selection
                updateAudioLanguageSummary()
                persistOverlayDefaults()
            }
        }
        subtitlesRow.card.setOnClickListener {
            showLanguageSearchDialog(
                titleRes = R.string.share_pref_dialog_subtitles,
                options = buildSubtitleOptions(),
                currentValue = subtitlesSelection,
            ) { selection ->
                subtitlesSelection = selection
                updateSubtitlesSummary()
                persistOverlayDefaults()
            }
        }

        updateResolutionSummary()
        updateFormatSummary()
        updateAudioFormatSummary()
        updateAudioLanguageSummary()
        updateSubtitlesSummary()
        updateOnlyAudioMode()

        val dismiss = {
            removeOverlay()
            stopSelf()
        }
        scrimView.setOnClickListener { dismiss() }
        styleSecondaryButton(cancelButton)
        stylePrimaryButton(confirmButton)
        cancelButton.setOnClickListener { dismiss() }
        closeButton.setOnClickListener { dismiss() }
        confirmButton.setOnClickListener {
            persistSelection()
            dismiss()
        }

        try {
            windowManager?.addView(view, params)
        } catch (error: Exception) {
            Toast.makeText(this, getString(R.string.share_overlay_error, error.message ?: ""), Toast.LENGTH_LONG).show()
            dismiss()
        }
    }

    private fun persistSelection() {
        val options = ManualDownloadOptions(
            onlyAudio = onlyAudioSelected,
            resolution = resolutionSelection,
            videoFormat = formatSelection,
            audioFormat = if (onlyAudioSelected) audioFormatSelection else null,
            audioLanguage = audioLanguageSelection,
            subtitles = subtitlesSelection,
        )
        val preferenceOverrides = mutableMapOf<String, Any?>(
            "playlist" to true,
        )
        val snapshot = payload?.copy(
            presetId = SharePresetIds.MANUAL,
            directShare = true,
        ) ?: return
        Log.d(
            TAG,
            "Persisting manual selection: audioOnly=$onlyAudioSelected res=$resolutionSelection videoFormat=$formatSelection audioFormat=$audioFormatSelection audioLang=$audioLanguageSelection subs=$subtitlesSelection",
        )
        PendingDownloadsStore.enqueue(
            context = this,
            payload = snapshot,
            presetId = SharePresetIds.MANUAL,
            options = options,
            preferenceOverrides = preferenceOverrides,
        )
        launchVidraApp(snapshot)
        persistOverlayDefaults()
        Toast.makeText(this, R.string.share_pending_manual_saved, Toast.LENGTH_SHORT).show()
    }

    private fun launchVidraApp(payload: ShareIntentPayload) {
        val shareText = resolveShareText(payload)
        val launchIntent = Intent(this@ManualOptionsOverlayService, MainActivity::class.java).apply {
            action = Intent.ACTION_SEND
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, shareText)
            if (!payload.subject.isNullOrBlank()) {
                putExtra(Intent.EXTRA_SUBJECT, payload.subject)
            }
            putExtra(MainActivity.EXTRA_SHARE_PRESET, SharePresetIds.MANUAL)
            putExtra(MainActivity.EXTRA_SHARE_DIRECT, true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        Log.d(TAG, "Starting MainActivity for manual share to trigger processing")
        startActivity(launchIntent)
    }

    private fun resolveShareText(payload: ShareIntentPayload): String {
        if (payload.rawText.isNotBlank()) {
            return payload.rawText
        }
        return payload.urls.joinToString(separator = "\n")
    }

    private fun loadPersistedSelections() {
        val context = applicationContext
        onlyAudioSelected = ManualOverlayPreferenceStore.readBoolean(
            context,
            PREF_ONLY_AUDIO,
            onlyAudioSelected,
        )
        resolutionSelection = ManualOverlayPreferenceStore.readString(
            context,
            PREF_RESOLUTION,
            resolutionSelection,
        ) ?: resolutionSelection
        formatSelection = ManualOverlayPreferenceStore.readString(
            context,
            PREF_VIDEO_FORMAT,
            formatSelection,
        ) ?: formatSelection
        audioFormatSelection = ManualOverlayPreferenceStore.readString(
            context,
            PREF_AUDIO_FORMAT,
            audioFormatSelection,
        ) ?: audioFormatSelection
        audioLanguageSelection = ManualOverlayPreferenceStore.readString(
            context,
            PREF_AUDIO_LANGUAGE,
            audioLanguageSelection,
        ) ?: audioLanguageSelection
        subtitlesSelection = ManualOverlayPreferenceStore.readString(
            context,
            PREF_SUBTITLES,
            subtitlesSelection,
        ) ?: subtitlesSelection
        Log.d(
            TAG,
            "Loaded persisted selections audioOnly=$onlyAudioSelected res=$resolutionSelection videoFormat=$formatSelection audioFormat=$audioFormatSelection audioLang=$audioLanguageSelection subs=$subtitlesSelection",
        )
    }

    private fun persistOverlayDefaults() {
        val context = applicationContext
        ManualOverlayPreferenceStore.writeBoolean(
            context,
            PREF_ONLY_AUDIO,
            onlyAudioSelected,
        )
        ManualOverlayPreferenceStore.writeString(
            context,
            PREF_RESOLUTION,
            resolutionSelection,
        )
        ManualOverlayPreferenceStore.writeString(
            context,
            PREF_VIDEO_FORMAT,
            formatSelection,
        )
        ManualOverlayPreferenceStore.writeString(
            context,
            PREF_AUDIO_FORMAT,
            audioFormatSelection,
        )
        ManualOverlayPreferenceStore.writeString(
            context,
            PREF_AUDIO_LANGUAGE,
            audioLanguageSelection,
        )
        ManualOverlayPreferenceStore.writeString(
            context,
            PREF_SUBTITLES,
            subtitlesSelection,
        )
    }

    private fun removeOverlay() {
        try {
            overlayView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {
        } finally {
            overlayView = null
        }
    }

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
    }

    private fun styleSheet(sheet: MaterialCardView, title: TextView, subtitle: TextView) {
        sheet.setCardBackgroundColor(palette.surface)
        val strokeWidthPx = max(1, resources.displayMetrics.density.toInt())
        sheet.strokeWidth = strokeWidthPx
        sheet.strokeColor = palette.outlineVariant
        val shapeBuilder = sheet.shapeAppearanceModel.toBuilder()
            .setTopLeftCorner(CornerFamily.ROUNDED, dp(28f))
            .setTopRightCorner(CornerFamily.ROUNDED, dp(28f))
            .setBottomLeftCorner(CornerFamily.ROUNDED, 0f)
            .setBottomRightCorner(CornerFamily.ROUNDED, 0f)
        sheet.shapeAppearanceModel = shapeBuilder.build()
        title.setTextColor(palette.onSurface)
        subtitle.setTextColor(palette.onSurfaceVariant)
    }

    private fun stylePrimaryButton(button: MaterialButton) {
        button.backgroundTintList = ColorStateList.valueOf(palette.primary)
        button.setTextColor(palette.onPrimary)
        button.rippleColor = ColorStateList.valueOf(
            ColorUtils.setAlphaComponent(palette.onPrimary, 50),
        )
    }

    private fun styleSecondaryButton(button: MaterialButton) {
        button.backgroundTintList = ColorStateList.valueOf(palette.secondary)
        button.setTextColor(palette.onSecondary)
        button.rippleColor = ColorStateList.valueOf(
            ColorUtils.setAlphaComponent(palette.onSecondary, 60),
        )
    }

    private fun stylePreferenceCard(
        card: MaterialCardView,
        iconCard: MaterialCardView,
        icon: ImageView,
    ) {
        card.setCardBackgroundColor(palette.surfaceVariant)
        card.strokeWidth = 0
        iconCard.setCardBackgroundColor(palette.primaryContainer)
        icon.setColorFilter(palette.onPrimaryContainer)
    }

    private fun styleSwitch(materialSwitch: SwitchMaterial) {
        val checkedState = intArrayOf(android.R.attr.state_checked)
        val uncheckedState = intArrayOf(-android.R.attr.state_checked)
        materialSwitch.trackTintList = ColorStateList(
            arrayOf(checkedState, uncheckedState),
            intArrayOf(
                ColorUtils.setAlphaComponent(palette.primary, 180),
                ColorUtils.setAlphaComponent(palette.outlineVariant, 200),
            ),
        )
        materialSwitch.thumbTintList = ColorStateList(
            arrayOf(checkedState, uncheckedState),
            intArrayOf(palette.onPrimary, palette.surface),
        )
    }

    private fun bindPreferenceRow(parent: View, iconRes: Int, titleRes: Int): PreferenceRow {
        val card = parent as MaterialCardView
        val iconCard: MaterialCardView = card.findViewById(R.id.pref_icon_container)
        val icon: ImageView = card.findViewById(R.id.pref_icon)
        val title: TextView = card.findViewById(R.id.pref_title)
        val value: TextView = card.findViewById(R.id.pref_value)
        val chevron: ImageView = card.findViewById(R.id.pref_chevron)
        stylePreferenceCard(card, iconCard, icon)
        title.setText(titleRes)
        title.setTextColor(palette.onSurface)
        value.setTextColor(palette.onSurfaceVariant)
        chevron.setColorFilter(palette.onSurfaceVariant)
        icon.setImageResource(iconRes)
        return PreferenceRow(card, iconCard, icon, title, value, chevron)
    }

    private fun buildLanguageEntries(): List<LanguageEntry> {
        val systemLocale = Locale.getDefault()
        val uniqueCodes = linkedSetOf<String>()
        Locale.getAvailableLocales().forEach { locale ->
            val languageCode = locale.language ?: return@forEach
            if (languageCode.length != 2 || languageCode == "und") {
                return@forEach
            }
            val normalized = languageCode.lowercase(Locale.US)
            if (normalized.isNotBlank()) {
                uniqueCodes.add(normalized)
            }
        }
        return uniqueCodes
            .map { code ->
                val display = Locale(code).getDisplayLanguage(systemLocale).ifBlank { code }
                val prettyName = display.replaceFirstChar { ch ->
                    if (ch.isLowerCase()) ch.titlecase(systemLocale) else ch.toString()
                }
                LanguageEntry(code, prettyName)
            }
            .sortedBy { it.displayName.lowercase(systemLocale) }
    }

    private fun buildLocalizedLanguageOptions(entries: List<LanguageEntry>): List<PreferenceOption> {
        val systemLocale = Locale.getDefault()
        return entries.map { entry ->
            val label = "${entry.displayName} (${entry.code.uppercase(systemLocale)})"
            PreferenceOption(entry.code, label)
        }
    }

    private fun buildResolutionOptions(): List<PreferenceOption> {
        val options = mutableListOf(
            option("best", R.string.share_pref_value_best),
            option("all", R.string.share_pref_value_all),
            option("4320", R.string.share_pref_value_8k),
            option("2160", R.string.share_pref_value_4k),
            option("1440", R.string.share_pref_value_2k),
            option("1080", R.string.share_pref_value_1080),
            option("720", R.string.share_pref_value_720),
            option("480", R.string.share_pref_value_480),
            option("360", R.string.share_pref_value_360),
        )
        options += listOf(
            optionLabel("240", "240p"),
            optionLabel("144", "144p"),
            option(null, R.string.share_pref_value_no_override),
        )
        return options
    }

    private fun buildFormatOptions(): List<PreferenceOption> {
        return listOf(
            option("mkv", R.string.share_pref_value_mkv),
            option("mp4", R.string.share_pref_value_mp4),
            option("webm", R.string.share_pref_value_webm),
            option("mov", R.string.share_pref_value_mov),
            option("flv", R.string.share_pref_value_flv),
            option("avi", R.string.share_pref_value_avi),
        )
    }

    private fun buildAudioFormatOptions(): List<PreferenceOption> {
        val options = mutableListOf(
            option("best", R.string.share_pref_value_best),
        )
        val formats = listOf("aac", "alac", "flac", "m4a", "mp3", "opus", "vorbis", "wav")
        formats.forEach { value ->
            options.add(optionLabel(value, value.uppercase(Locale.US)))
        }
        return options
    }

    private fun buildAudioLanguageOptions(): List<PreferenceOption> {
        val options = mutableListOf(
            option("best", R.string.share_pref_value_best),
            option(null, R.string.share_pref_value_auto_audio),
            option("all", R.string.share_pref_value_all),
        )
        options.addAll(localizedLanguageOptions)
        return options
    }

    private fun buildSubtitleOptions(): List<PreferenceOption> {
        val options = mutableListOf(
            option("none", R.string.share_pref_value_none),
            option("all", R.string.share_pref_value_all),
        )
        options.addAll(localizedLanguageOptions)
        return options
    }

    private fun option(value: String?, labelRes: Int, isCustom: Boolean = false): PreferenceOption {
        return PreferenceOption(value, getString(labelRes), isCustom)
    }

    private fun optionLabel(value: String?, label: String, isCustom: Boolean = false): PreferenceOption {
        return PreferenceOption(value, label, isCustom)
    }

    private fun showChoiceDialog(
        titleRes: Int,
        options: List<PreferenceOption>,
        currentValue: String?,
        onSelected: (String?) -> Unit,
    ) {
        val labels = options.map { it.label }.toTypedArray()
        val currentIndex = options.indexOfFirst { option ->
            if (option.isCustom) {
                false
            } else {
                (option.value ?: "").equals(currentValue ?: "", ignoreCase = true)
            }
        }
        val builder = MaterialAlertDialogBuilder(overlayThemeContext)
            .setTitle(titleRes)
            .setSingleChoiceItems(labels, currentIndex) { dialog, which ->
                val option = options[which]
                if (option.isCustom) {
                    dialog.dismiss()
                    promptForCustomValue(titleRes, currentValue, onSelected)
                } else {
                    dialog.dismiss()
                    onSelected(option.value)
                }
            }
            .setNegativeButton(R.string.share_pref_dialog_cancel, null)
        val dialog = builder.create()
        dialog.window?.setType(overlayWindowType())
        dialog.show()
    }

    private fun showLanguageSearchDialog(
        titleRes: Int,
        options: List<PreferenceOption>,
        currentValue: String?,
        onSelected: (String?) -> Unit,
    ) {
        val dialogView = LayoutInflater.from(overlayThemeContext)
            .inflate(R.layout.dialog_searchable_list, null)
        val searchInputLayout = dialogView.findViewById<TextInputLayout>(R.id.search_input_layout)
        val searchInput = dialogView.findViewById<TextInputEditText>(R.id.search_input)
        val listView = dialogView.findViewById<ListView>(R.id.search_list)
        searchInputLayout.hint = getString(R.string.share_pref_search_hint)
        val adapter = LanguageOptionAdapter(options)
        listView.adapter = adapter
        val dialog = MaterialAlertDialogBuilder(overlayThemeContext)
            .setTitle(titleRes)
            .setView(dialogView)
            .setNegativeButton(R.string.share_pref_dialog_cancel, null)
            .create()
        listView.setOnItemClickListener { _, _, position, _ ->
            val option = adapter.getItem(position)
            dialog.dismiss()
            onSelected(option.value)
        }
        val normalized = currentValue?.lowercase(Locale.US)
        val index = options.indexOfFirst { option ->
            if (normalized == null) {
                option.value == null
            } else {
                (option.value ?: "").lowercase(Locale.US) == normalized
            }
        }
        if (index >= 0) {
            listView.setSelection(index)
        }
        searchInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                adapter.updateQuery(s?.toString().orEmpty())
            }
            override fun afterTextChanged(s: Editable?) {}
        })
        dialog.window?.setType(overlayWindowType())
        dialog.show()
    }

    private fun promptForCustomValue(
        titleRes: Int,
        currentValue: String?,
        onSelected: (String?) -> Unit,
    ) {
        val inputLayout = TextInputLayout(overlayThemeContext)
        val editText = TextInputEditText(inputLayout.context)
        inputLayout.hint = getString(R.string.share_pref_custom_hint)
        inputLayout.addView(editText)
        editText.setText(currentValue)
        val padding = (16 * resources.displayMetrics.density).toInt()
        inputLayout.setPadding(padding, 0, padding, 0)
        val builder = MaterialAlertDialogBuilder(overlayThemeContext)
            .setTitle(titleRes)
            .setView(inputLayout)
            .setPositiveButton(R.string.share_pref_custom_save) { _, _ ->
                val value = editText.text?.toString()?.trim().orEmpty()
                onSelected(value.ifEmpty { null })
            }
            .setNegativeButton(R.string.share_pref_dialog_cancel, null)
        val dialog = builder.create()
        dialog.window?.setType(overlayWindowType())
        dialog.show()
    }

    private fun updateResolutionSummary() {
        val text = when (val value = resolutionSelection) {
            null -> getString(R.string.share_pref_value_no_override)
            "all" -> getString(R.string.share_pref_value_all)
            "best" -> getString(R.string.share_pref_value_best)
            "4320" -> getString(R.string.share_pref_value_8k)
            "2160" -> getString(R.string.share_pref_value_4k)
            "1440" -> getString(R.string.share_pref_value_2k)
            "1080" -> getString(R.string.share_pref_value_1080)
            "720" -> getString(R.string.share_pref_value_720)
            "480" -> getString(R.string.share_pref_value_480)
            "360" -> getString(R.string.share_pref_value_360)
            else -> value + "p"
        }
        resolutionRow.value.text = text
    }

    private fun updateFormatSummary() {
        val text = when (val value = formatSelection) {
            null -> getString(R.string.share_pref_value_no_override)
            else -> value.uppercase()
        }
        formatRow.value.text = text
    }

    private fun updateAudioFormatSummary() {
        val text = when (val value = audioFormatSelection) {
            null -> getString(R.string.share_pref_value_no_override)
            "best" -> getString(R.string.share_pref_value_best)
            else -> value.uppercase(Locale.US)
        }
        audioFormatRow.value.text = text
    }

    private fun updateAudioLanguageSummary() {
        val text = when (val value = audioLanguageSelection) {
            null -> getString(R.string.share_pref_value_auto_audio)
            "best" -> getString(R.string.share_pref_value_best)
            "all" -> getString(R.string.share_pref_value_all)
            else -> languageLabelMap[value.lowercase(Locale.US)] ?: value.uppercase(Locale.US)
        }
        audioLanguageRow.value.text = text
    }

    private fun updateSubtitlesSummary() {
        val text = when (val value = subtitlesSelection) {
            null, "none" -> getString(R.string.share_pref_value_none)
            "all" -> getString(R.string.share_pref_value_all)
            else -> languageLabelMap[value.lowercase(Locale.US)] ?: value.uppercase(Locale.US)
        }
        subtitlesRow.value.text = text
    }

    private fun updateOnlyAudioMode() {
        if (
            !::videoOptionsContainer.isInitialized ||
            !::audioOnlyOptionsContainer.isInitialized ||
            !::onlyAudioTitle.isInitialized ||
            !::onlyAudioDesc.isInitialized ||
            !::onlyAudioIcon.isInitialized
        ) {
            return
        }
        val visibilityVideo = if (onlyAudioSelected) View.GONE else View.VISIBLE
        val visibilityAudio = if (onlyAudioSelected) View.VISIBLE else View.GONE
        videoOptionsContainer.visibility = visibilityVideo
        audioOnlyOptionsContainer.visibility = visibilityAudio
        val titleRes = if (onlyAudioSelected) {
            R.string.share_pref_title_only_audio
        } else {
            R.string.share_pref_title_audio_video
        }
        val descRes = if (onlyAudioSelected) {
            R.string.share_pref_desc_audio_video
        } else {
            R.string.share_pref_desc_only_audio
        }
        val iconRes = if (onlyAudioSelected) {
            R.drawable.ic_pref_audio_only
        } else {
            R.drawable.ic_pref_format
        }
        onlyAudioTitle.setText(titleRes)
        onlyAudioDesc.setText(descRes)
        onlyAudioIcon.setImageResource(iconRes)
    }

    private fun overlayWindowType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }

    private fun dp(value: Float): Float {
        return value * resources.displayMetrics.density
    }

    private inner class LanguageOptionAdapter(
        private val options: List<PreferenceOption>,
    ) : BaseAdapter() {

        private var filtered: List<PreferenceOption> = options

        override fun getCount(): Int = filtered.size

        override fun getItem(position: Int): PreferenceOption = filtered[position]

        override fun getItemId(position: Int): Long = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup?): View {
            val textView = convertView as? TextView
                ?: LayoutInflater.from(overlayThemeContext)
                    .inflate(android.R.layout.simple_list_item_1, parent, false) as TextView
            textView.text = filtered[position].label
            textView.setTextColor(palette.onSurface)
            textView.setPaddingRelative(textView.paddingStart, 12, textView.paddingEnd, 12)
            return textView
        }

        fun updateQuery(query: String) {
            val normalized = query.trim().lowercase(Locale.getDefault())
            filtered = if (normalized.isEmpty()) {
                options
            } else {
                options.filter { option ->
                    option.label.lowercase(Locale.getDefault()).contains(normalized) ||
                        (option.value?.lowercase(Locale.getDefault())?.contains(normalized) == true)
                }
            }
            notifyDataSetChanged()
        }
    }
}
