# Keep Flutter embedding and plugins (common baseline for Flutter apps).
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }

# Keep the generated plugin registrant.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# If you use reflection-based libraries, add keep rules here.
