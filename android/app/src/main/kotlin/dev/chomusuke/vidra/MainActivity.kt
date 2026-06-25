package dev.chomusuke.vidra

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
//import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "vidra_channel"

//    override fun getBackgroundMode(): BackgroundMode {
//      return BackgroundMode.transparent
//    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getNativeLibDir") {
                result.success(context.applicationInfo.nativeLibraryDir)
            } else if (call.method == "moveToBackground") {
                // moveTaskToBack(true) es el equivalente exacto a que el usuario presione el botón Home
                moveTaskToBack(true) 
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }
}