package dev.chomusuke.vidra.share

import android.content.Context
import android.content.res.Configuration
import androidx.annotation.ColorInt

/**
 * Mirrors the ColorScheme definitions declared in Flutter's main.dart so the
 * native overlay can reuse the same palette when Flutter isn't in the foreground.
 */
object FlutterThemePalette {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_THEME_DARK = "flutter.theme_dark"

    data class Palette(
        @ColorInt val primary: Int,
        @ColorInt val onPrimary: Int,
        @ColorInt val primaryContainer: Int,
        @ColorInt val onPrimaryContainer: Int,
        @ColorInt val secondary: Int,
        @ColorInt val onSecondary: Int,
        @ColorInt val surface: Int,
        @ColorInt val onSurface: Int,
        @ColorInt val surfaceVariant: Int,
        @ColorInt val onSurfaceVariant: Int,
        @ColorInt val outline: Int,
        @ColorInt val outlineVariant: Int,
        @ColorInt val background: Int,
        @ColorInt val onBackground: Int,
        @ColorInt val tertiary: Int,
    )

    private val lightPalette = Palette(
        primary = 0xFF36618E.toInt(),
        onPrimary = 0xFFFFFFFF.toInt(),
        primaryContainer = 0xFFD1E4FF.toInt(),
        onPrimaryContainer = 0xFF001D36.toInt(),
        secondary = 0xFF535F70.toInt(),
        onSecondary = 0xFFFFFFFF.toInt(),
        surface = 0xFFF8F9FF.toInt(),
        onSurface = 0xFF191C20.toInt(),
        surfaceVariant = 0xFFDFE2EB.toInt(),
        onSurfaceVariant = 0xFF43474E.toInt(),
        outline = 0xFF73777F.toInt(),
        outlineVariant = 0xFFC3C7CF.toInt(),
        background = 0xFFF8F9FF.toInt(),
        onBackground = 0xFF191C20.toInt(),
        tertiary = 0xFF6B5778.toInt(),
    )

    private val darkPalette = Palette(
        primary = 0xFF82D5C8.toInt(),
        onPrimary = 0xFF003731.toInt(),
        primaryContainer = 0xFF005048.toInt(),
        onPrimaryContainer = 0xFF9EF2E4.toInt(),
        secondary = 0xFFB1CCC6.toInt(),
        onSecondary = 0xFF1C3531.toInt(),
        surface = 0xFF0E1513.toInt(),
        onSurface = 0xFFDDE4E1.toInt(),
        surfaceVariant = 0xFF3F4947.toInt(),
        onSurfaceVariant = 0xFFBEC9C6.toInt(),
        outline = 0xFF899390.toInt(),
        outlineVariant = 0xFF3F4947.toInt(),
        background = 0xFF0E1513.toInt(),
        onBackground = 0xFFDDE4E1.toInt(),
        tertiary = 0xFFADCAE6.toInt(),
    )

    fun resolve(context: Context): Palette {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val stored = if (prefs.contains(KEY_THEME_DARK)) {
            prefs.getBoolean(KEY_THEME_DARK, false)
        } else {
            null
        }
        val isDark = stored ?: isSystemDark(context)
        return if (isDark) darkPalette else lightPalette
    }

    private fun isSystemDark(context: Context): Boolean {
        val nightModeFlags = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return nightModeFlags == Configuration.UI_MODE_NIGHT_YES
    }
}
