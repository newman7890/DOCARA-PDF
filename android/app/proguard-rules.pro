# Keep ML Kit optional language model classes to suppress R8 missing class errors
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Google ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_** { *; }

# Keep Play Core (Required for some Flutter plugins)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep app classes
-keep class com.example.pdf_scanner_editor.** { *; }
