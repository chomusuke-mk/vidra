package dev.chomusuke.vidra.share

import android.content.ComponentName
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.service.chooser.ChooserTarget
import android.service.chooser.ChooserTargetService
import androidx.annotation.RequiresApi
import dev.chomusuke.vidra.MainActivity
import dev.chomusuke.vidra.R

@RequiresApi(Build.VERSION_CODES.M)
class ShareShortcutService : ChooserTargetService() {
    private data class ShortcutDefinition(
        val presetId: String,
        val labelRes: Int,
    )

    private val shortcuts = listOf(
        ShortcutDefinition(
            SharePresetIds.VIDEO_BEST,
            R.string.share_target_video_best,
        ),
        ShortcutDefinition(
            SharePresetIds.AUDIO_BEST,
            R.string.share_target_audio_best,
        ),
        ShortcutDefinition(
            SharePresetIds.MANUAL,
            R.string.share_target_manual,
        ),
    )

    override fun onGetChooserTargets(
        targetActivityComponentName: ComponentName,
        matchedFilter: IntentFilter,
    ): List<ChooserTarget> {
        if (targetActivityComponentName.className != MainActivity::class.java.name) {
            return emptyList()
        }
        val icon = Icon.createWithResource(this, R.mipmap.ic_launcher)
        val targets = ArrayList<ChooserTarget>(shortcuts.size)
        val componentName = ComponentName(this, MainActivity::class.java)
        shortcuts.forEachIndexed { index, shortcut ->
            val bundle = Bundle().apply {
                putString(MainActivity.EXTRA_SHARE_PRESET, shortcut.presetId)
                putBoolean(MainActivity.EXTRA_SHARE_DIRECT, true)
            }
            targets.add(ChooserTarget(
                getString(shortcut.labelRes),
                icon,
                1.0f - (index * 0.2f),
                componentName,
                bundle,
            ))
        }
        return targets
    }

}
