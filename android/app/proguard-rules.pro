# Flutter Play Core — app doesn't use deferred components; suppress R8 missing class errors
-dontwarn com.google.android.play.core.**

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Hive
-keep class ** extends com.google.flatbuffers.Table { *; }

# Record
-keep class com.llfbandit.record.** { *; }

# JustAudio
-keep class com.ryanheise.just_audio.** { *; }
