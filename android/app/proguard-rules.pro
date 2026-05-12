# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# SharedPreferences
-keep class androidx.preference.** { *; }
-keep class android.preference.** { *; }

# Remove warnings about other deprecated classes
-dontwarn android.**
-dontwarn io.flutter.**

# Keep Kotlin classes
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }