package com.selvavishnu.clearwave

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {

    companion object {
        private const val VIDEO_CHANNEL = "com.selvavishnu.clearwave/video"
        private const val AUDIO_CHANNEL = "com.selvavishnu.clearwave/audio"
    }

    private val videoProcessor = VideoAudioProcessor()
    private val deepFilter     = DeepFilterProcessor()
    private val handler        = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Video channel ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VIDEO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractAudioToWav" -> {
                        val videoPath  = call.argument<String>("videoPath")  ?: run { result.error("ARG", "videoPath missing", null);  return@setMethodCallHandler }
                        val outputPath = call.argument<String>("outputPath") ?: run { result.error("ARG", "outputPath missing", null); return@setMethodCallHandler }
                        Thread {
                            val ok = videoProcessor.extractAudioToWav(videoPath, outputPath)
                            handler.post { result.success(ok) }
                        }.start()
                    }
                    "muxProcessedAudioIntoVideo" -> {
                        val videoPath  = call.argument<String>("videoPath")  ?: run { result.error("ARG", "videoPath missing", null);  return@setMethodCallHandler }
                        val wavPath    = call.argument<String>("wavPath")    ?: run { result.error("ARG", "wavPath missing", null);    return@setMethodCallHandler }
                        val outputPath = call.argument<String>("outputPath") ?: run { result.error("ARG", "outputPath missing", null); return@setMethodCallHandler }
                        Thread {
                            val ok = videoProcessor.muxProcessedAudioIntoVideo(videoPath, wavPath, outputPath)
                            handler.post { result.success(ok) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Audio / DeepFilter channel ─────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initDeepFilter" -> {
                        Thread {
                            val ok = deepFilter.initialize(applicationContext)
                            handler.post { result.success(ok) }
                        }.start()
                    }
                    "deepFilter" -> {
                        val pcmBytes = call.argument<ByteArray>("pcm")  ?: run { result.error("ARG", "pcm missing", null);  return@setMethodCallHandler }
                        val rate     = call.argument<Int>("rate")        ?: run { result.error("ARG", "rate missing", null); return@setMethodCallHandler }

                        // Deserialise Float32List bytes → FloatArray
                        val buf = ByteBuffer.wrap(pcmBytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
                        val input = FloatArray(buf.remaining()).also { buf.get(it) }

                        Thread {
                            try {
                                val enhanced = deepFilter.process(input, rate)
                                // Serialise FloatArray → bytes
                                val outBuf = ByteBuffer.allocate(enhanced.size * 4).order(ByteOrder.LITTLE_ENDIAN)
                                enhanced.forEach { outBuf.putFloat(it) }
                                handler.post { result.success(outBuf.array()) }
                            } catch (e: Exception) {
                                handler.post { result.error("DF", e.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
