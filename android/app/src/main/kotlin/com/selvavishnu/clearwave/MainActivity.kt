package com.selvavishnu.clearwave

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.selvavishnu.clearwave/video"
    }

    private val processor = VideoAudioProcessor()
    private val handler   = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractAudioToWav" -> {
                        val videoPath  = call.argument<String>("videoPath") ?: run { result.error("ARG", "videoPath missing", null); return@setMethodCallHandler }
                        val outputPath = call.argument<String>("outputPath") ?: run { result.error("ARG", "outputPath missing", null); return@setMethodCallHandler }
                        Thread {
                            val ok = processor.extractAudioToWav(videoPath, outputPath)
                            handler.post { result.success(ok) }
                        }.start()
                    }
                    "muxProcessedAudioIntoVideo" -> {
                        val videoPath  = call.argument<String>("videoPath") ?: run { result.error("ARG", "videoPath missing", null); return@setMethodCallHandler }
                        val wavPath    = call.argument<String>("wavPath") ?: run { result.error("ARG", "wavPath missing", null); return@setMethodCallHandler }
                        val outputPath = call.argument<String>("outputPath") ?: run { result.error("ARG", "outputPath missing", null); return@setMethodCallHandler }
                        Thread {
                            val ok = processor.muxProcessedAudioIntoVideo(videoPath, wavPath, outputPath)
                            handler.post { result.success(ok) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
