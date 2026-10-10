package dev.chomusuke.vidra

import android.media.MediaScannerConnection
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
//import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "vidra_channel"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNativeLibDir" -> {
                    result.success(context.applicationInfo.nativeLibraryDir)
                }
                "moveToBackground" -> {
                    runOnUiThread {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                }
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    val mimeType = call.argument<String>("mimeType")
                    if (!path.isNullOrEmpty()) {
                        var replied = false
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(path),
                            if (mimeType != null) arrayOf(mimeType) else null
                        ) { _, uri ->
                            runOnUiThread {
                                if (!replied) {
                                    replied = true
                                    result.success(uri?.toString())
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_PATH", "Path is null or empty", null)
                    }
                }
                "scanFiles" -> {
                    val paths = call.argument<List<String>>("paths")
                    if (!paths.isNullOrEmpty()) {
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            paths.toTypedArray(),
                            null
                        ) { _, _ -> }
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}