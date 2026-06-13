package com.noiseclear.app

import android.media.*
import android.util.Log
import java.io.*
import java.nio.ByteBuffer
import java.nio.ByteOrder

class VideoAudioProcessor {

    companion object {
        private const val TAG = "VideoAudioProcessor"
        private const val TIMEOUT_US = 10_000L
    }

    // ── Extract audio from a video file and write as 44100 Hz mono WAV ────────

    fun extractAudioToWav(videoPath: String, wavOutputPath: String): Boolean {
        return try {
            val extractor = MediaExtractor()
            extractor.setDataSource(videoPath)

            val audioIdx = findAudioTrack(extractor)
            if (audioIdx < 0) { extractor.release(); return false }

            extractor.selectTrack(audioIdx)
            val format = extractor.getTrackFormat(audioIdx)
            val mime   = format.getString(MediaFormat.KEY_MIME) ?: run { extractor.release(); return false }
            val srcRate     = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val srcChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

            val decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(format, null, null, 0)
            decoder.start()

            val pcmShorts = decodeToPcm(extractor, decoder)
            decoder.stop(); decoder.release(); extractor.release()

            val finalPcm = if (srcRate != 44100 || srcChannels != 1)
                toMono44k(pcmShorts, srcRate, srcChannels)
            else pcmShorts

            writeWav(finalPcm, 44100, 1, wavOutputPath)
            true
        } catch (e: Exception) {
            Log.e(TAG, "extractAudioToWav", e)
            false
        }
    }

    // ── Replace audio track in video with processed WAV ───────────────────────

    fun muxProcessedAudioIntoVideo(videoPath: String, wavPath: String, outputPath: String): Boolean {
        return try {
            val pcmBytes = readPcmFromWav(wavPath)

            // ── Step 1: encode PCM → AAC, collect all frames + output format ──
            val encFmt = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, 44100, 1)
            encFmt.setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
            encFmt.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            encFmt.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 65536)

            val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            encoder.configure(encFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()

            data class AudioChunk(val data: ByteArray, val pts: Long)
            val aacChunks   = mutableListOf<AudioChunk>()
            var audioFmt: MediaFormat? = null
            var inOffset    = 0
            var inputDone   = false
            val bufInfo     = MediaCodec.BufferInfo()

            while (audioFmt == null || !inputDone || aacChunks.isEmpty()) {
                if (!inputDone) {
                    val inIdx = encoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inIdx >= 0) {
                        val buf = encoder.getInputBuffer(inIdx)!!
                        buf.clear()
                        val rem = pcmBytes.size - inOffset
                        if (rem <= 0) {
                            encoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            val chunk = minOf(buf.capacity(), rem)
                            buf.put(pcmBytes, inOffset, chunk)
                            val pts = inOffset.toLong() * 1_000_000L / (44100 * 2)
                            encoder.queueInputBuffer(inIdx, 0, chunk, pts, 0)
                            inOffset += chunk
                        }
                    }
                }
                when (val outIdx = encoder.dequeueOutputBuffer(bufInfo, TIMEOUT_US)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> audioFmt = encoder.outputFormat
                    MediaCodec.INFO_TRY_AGAIN_LATER      -> { /* spin */ }
                    else -> if (outIdx >= 0) {
                        val outBuf = encoder.getOutputBuffer(outIdx)!!
                        if (bufInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                            val bytes = ByteArray(bufInfo.size)
                            outBuf.get(bytes)
                            aacChunks.add(AudioChunk(bytes, bufInfo.presentationTimeUs))
                        }
                        encoder.releaseOutputBuffer(outIdx, false)
                        if (bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    }
                }
                // exit loop once input done and all output drained
                if (inputDone && audioFmt != null) {
                    val outIdx = encoder.dequeueOutputBuffer(bufInfo, TIMEOUT_US)
                    if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        audioFmt = encoder.outputFormat
                    } else if (outIdx >= 0) {
                        val outBuf = encoder.getOutputBuffer(outIdx)!!
                        if (bufInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                            val bytes = ByteArray(bufInfo.size)
                            outBuf.get(bytes)
                            aacChunks.add(AudioChunk(bytes, bufInfo.presentationTimeUs))
                        }
                        encoder.releaseOutputBuffer(outIdx, false)
                        if (bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    }
                }
            }
            encoder.stop(); encoder.release()

            // ── Step 2: mux original video + encoded audio ─────────────────────
            val videoExtractor = MediaExtractor()
            videoExtractor.setDataSource(videoPath)
            val videoTrackIdx = findVideoTrack(videoExtractor)
            if (videoTrackIdx < 0) { videoExtractor.release(); return false }
            videoExtractor.selectTrack(videoTrackIdx)
            val videoFormat = videoExtractor.getTrackFormat(videoTrackIdx)

            val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val muxVideoIdx = muxer.addTrack(videoFormat)
            val muxAudioIdx = muxer.addTrack(audioFmt ?: return false)
            muxer.start()

            // write video frames
            val vBuf  = ByteBuffer.allocate(512 * 1024)
            val vInfo = MediaCodec.BufferInfo()
            while (true) {
                vBuf.clear()
                val sz = videoExtractor.readSampleData(vBuf, 0)
                if (sz < 0) break
                vInfo.offset = 0; vInfo.size = sz
                vInfo.presentationTimeUs = videoExtractor.sampleTime
                vInfo.flags = videoExtractor.sampleFlags
                muxer.writeSampleData(muxVideoIdx, vBuf, vInfo)
                videoExtractor.advance()
            }

            // write audio frames
            val aInfo = MediaCodec.BufferInfo()
            aInfo.offset = 0; aInfo.flags = 0
            for ((data, pts) in aacChunks) {
                val aBuf = ByteBuffer.wrap(data)
                aInfo.size = data.size; aInfo.presentationTimeUs = pts
                muxer.writeSampleData(muxAudioIdx, aBuf, aInfo)
            }

            muxer.stop(); muxer.release()
            videoExtractor.release()
            true
        } catch (e: Exception) {
            Log.e(TAG, "muxProcessedAudioIntoVideo", e)
            false
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun findAudioTrack(extractor: MediaExtractor): Int {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) return i
        }
        return -1
    }

    private fun findVideoTrack(extractor: MediaExtractor): Int {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("video/")) return i
        }
        return -1
    }

    private fun decodeToPcm(extractor: MediaExtractor, codec: MediaCodec): ShortArray {
        val out    = ArrayList<Short>(64 * 1024)
        val info   = MediaCodec.BufferInfo()
        var sawEOS = false

        loop@ while (true) {
            if (!sawEOS) {
                val inIdx = codec.dequeueInputBuffer(TIMEOUT_US)
                if (inIdx >= 0) {
                    val buf  = codec.getInputBuffer(inIdx)!!
                    val size = extractor.readSampleData(buf, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        sawEOS = true
                    } else {
                        codec.queueInputBuffer(inIdx, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            when (val outIdx = codec.dequeueOutputBuffer(info, TIMEOUT_US)) {
                MediaCodec.INFO_TRY_AGAIN_LATER,
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> { /* continue */ }
                else -> if (outIdx >= 0) {
                    val outBuf = codec.getOutputBuffer(outIdx)!!
                    outBuf.rewind()
                    val sb = outBuf.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                    repeat(sb.remaining()) { out.add(sb.get()) }
                    codec.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break@loop
                }
            }
            if (sawEOS && codec.dequeueOutputBuffer(info, 0) == MediaCodec.INFO_TRY_AGAIN_LATER) break
        }
        return out.toShortArray()
    }

    private fun toMono44k(input: ShortArray, srcRate: Int, channels: Int): ShortArray {
        val mono = if (channels > 1) {
            ShortArray(input.size / channels) { i ->
                var sum = 0L
                for (c in 0 until channels) sum += input[i * channels + c]
                (sum / channels).toShort()
            }
        } else input

        if (srcRate == 44100) return mono
        val ratio = 44100.0 / srcRate
        val len   = (mono.size * ratio).toInt()
        return ShortArray(len) { i ->
            val src = (i / ratio).toInt().coerceIn(0, mono.size - 1)
            mono[src]
        }
    }

    private fun writeWav(pcm: ShortArray, rate: Int, channels: Int, path: String) {
        val dataLen = pcm.size * 2
        DataOutputStream(BufferedOutputStream(FileOutputStream(path))).use { d ->
            d.write("RIFF".toByteArray())
            d.intLE(36 + dataLen)
            d.write("WAVEfmt ".toByteArray())
            d.intLE(16); d.shortLE(1); d.shortLE(channels)
            d.intLE(rate); d.intLE(rate * channels * 2)
            d.shortLE(channels * 2); d.shortLE(16)
            d.write("data".toByteArray()); d.intLE(dataLen)
            for (s in pcm) d.shortLE(s.toInt())
        }
    }

    private fun readPcmFromWav(wavPath: String): ByteArray {
        RandomAccessFile(wavPath, "r").use { f ->
            f.seek(44)
            val bytes = ByteArray((f.length() - 44).toInt())
            f.readFully(bytes)
            return bytes
        }
    }

    private fun DataOutputStream.intLE(v: Int)  = write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v).array())
    private fun DataOutputStream.shortLE(v: Int) = write(ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN).putShort(v.toShort()).array())
}
