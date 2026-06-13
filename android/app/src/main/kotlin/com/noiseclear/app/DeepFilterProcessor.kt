package com.noiseclear.app

import ai.onnxruntime.*
import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.*

/**
 * DeepFilterNet2 on-device inference.
 *
 * Pipeline per 10ms frame (480 samples @ 48 kHz):
 *   1. Hann-windowed STFT (FFT=960, non-power-of-2 → Bluestein's algorithm)
 *   2. ERB energy features  [1, NB_ERB]
 *   3. Encoder   enc.onnx   → embedding + skip features
 *   4. ERB decoder erb_dec.onnx → magnitude gains [NB_ERB]
 *   5. DF  decoder df_dec.onnx  → complex ratio filter [NB_DF, DF_ORDER]
 *   6. Apply gains (ERB) + FIR filter (DF)
 *   7. iSTFT overlap-add → 480 output samples
 */
class DeepFilterProcessor(private val context: Context) {

    companion object {
        private const val TAG = "DeepFilterProcessor"

        const val SR         = 48_000
        const val FFT_SIZE   = 960
        const val HOP_SIZE   = 480
        const val FREQ_BINS  = FFT_SIZE / 2 + 1   // 481
        const val NB_ERB     = 32
        const val NB_DF      = 96
        const val DF_ORDER   = 5
        const val ENC_HIDDEN = 256
        const val DEC_HIDDEN = 64

        // ERB band boundary bins for 48 kHz / FFT 960 / 32 bands
        val ERB_BINS: IntArray = buildErbBins()

        private fun buildErbBins(): IntArray {
            val res = SR.toFloat() / FFT_SIZE
            fun hz2erb(f: Float) = 21.4f * log10(0.00437f * f + 1f)
            val lo = hz2erb(0f); val hi = hz2erb(SR / 2f)
            return IntArray(NB_ERB + 1) { b ->
                val erb = lo + (hi - lo) * b / NB_ERB
                val hz  = (10f.pow(erb / 21.4f) - 1f) / 0.00437f
                (hz / res).roundToInt().coerceIn(0, FREQ_BINS - 1)
            }
        }
    }

    private val ortEnv: OrtEnvironment = OrtEnvironment.getEnvironment()
    private var encSess:    OrtSession? = null
    private var erbDecSess: OrtSession? = null
    private var dfDecSess:  OrtSession? = null

    // GRU hidden states  shape [num_layers, 1, hidden]
    private var hEnc0 = FloatArray(ENC_HIDDEN); private var hEnc1 = FloatArray(ENC_HIDDEN)
    private var hErb0 = FloatArray(DEC_HIDDEN); private var hErb1 = FloatArray(DEC_HIDDEN)
    private var hDf0  = FloatArray(DEC_HIDDEN); private var hDf1  = FloatArray(DEC_HIDDEN)

    // DF past-frames circular buffer  [DF_ORDER, NB_DF, 2]
    private val dfBuf    = Array(DF_ORDER) { Array(NB_DF) { FloatArray(2) } }
    private var dfBufIdx = 0

    // STFT overlap buffers
    private val analysisBuf = FloatArray(FFT_SIZE)   // sliding window of input
    private val synthBuf    = FloatArray(FFT_SIZE)   // overlap-add accumulator

    private val window = FloatArray(FFT_SIZE) { i ->
        0.5f * (1f - cos(2.0 * PI * i / FFT_SIZE).toFloat())
    }

    // ── Initialisation ────────────────────────────────────────────────────────

    fun initialize(): Boolean {
        return try {
            val dir = extractModels() ?: return false
            val opts = OrtSession.SessionOptions().apply {
                setIntraOpNumThreads(2)
                setOptimizationLevel(OrtSession.SessionOptions.OptLevel.EXTENDED_OPT)
            }
            encSess    = ortEnv.createSession("$dir/enc.onnx",     opts)
            erbDecSess = ortEnv.createSession("$dir/erb_dec.onnx", opts)
            dfDecSess  = ortEnv.createSession("$dir/df_dec.onnx",  opts)
            resetState()
            Log.i(TAG, "DeepFilterNet initialized  enc=${encSess!!.inputNames}  erb=${erbDecSess!!.inputNames}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "DeepFilterNet init failed", e); false
        }
    }

    fun isReady() = encSess != null

    fun resetState() {
        hEnc0 = FloatArray(ENC_HIDDEN); hEnc1 = FloatArray(ENC_HIDDEN)
        hErb0 = FloatArray(DEC_HIDDEN); hErb1 = FloatArray(DEC_HIDDEN)
        hDf0  = FloatArray(DEC_HIDDEN); hDf1  = FloatArray(DEC_HIDDEN)
        for (d in 0 until DF_ORDER) for (f in 0 until NB_DF) dfBuf[d][f].fill(0f)
        dfBufIdx = 0
        analysisBuf.fill(0f); synthBuf.fill(0f)
    }

    /** Copies the three ONNX model assets into app cacheDir/deepfilter/ */
    private fun extractModels(): String? {
        val dir = File(context.cacheDir, "deepfilter")
        dir.mkdirs()
        val models = listOf("enc.onnx", "erb_dec.onnx", "df_dec.onnx")
        for (name in models) {
            val dst = File(dir, name)
            if (!dst.exists() || dst.length() == 0L) {
                val assetPath = "flutter_assets/assets/models/$name"
                try {
                    context.assets.open(assetPath).use { src ->
                        FileOutputStream(dst).use { src.copyTo(it) }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Missing model asset: $assetPath"); return null
                }
            }
        }
        return dir.absolutePath
    }

    // ── Main entry ────────────────────────────────────────────────────────────

    /**
     * Denoise [inputPcm] at [inputRate] Hz mono.
     *
     * [isolator] = premium Voice Isolator mode: runs a second neural refinement
     * pass over the first pass output for maximum voice isolation (≈ studio
     * "isolate voice" quality). Free tier uses a single pass.
     *
     * Returns enhanced audio at the same sample rate.
     */
    fun process(inputPcm: FloatArray, inputRate: Int, isolator: Boolean = false): FloatArray {
        val first = runPipeline(inputPcm, inputRate)
        if (!isolator) return first
        // Premium: second aggressive pass on a clean GRU state.
        resetState()
        return runPipeline(first, inputRate)
    }

    private fun runPipeline(inputPcm: FloatArray, inputRate: Int): FloatArray {
        val wav48 = if (inputRate == SR) inputPcm else resample(inputPcm, inputRate, SR)
        val out   = FloatArray(wav48.size)
        var outPos = 0

        var pos = 0
        while (pos + HOP_SIZE <= wav48.size) {
            // Slide analysis window
            System.arraycopy(analysisBuf, HOP_SIZE, analysisBuf, 0, FFT_SIZE - HOP_SIZE)
            System.arraycopy(wav48, pos, analysisBuf, FFT_SIZE - HOP_SIZE, HOP_SIZE)

            val frame = processFrame()
            val copy  = minOf(HOP_SIZE, out.size - outPos)
            frame.copyInto(out, outPos, 0, copy)
            outPos += copy
            pos    += HOP_SIZE
        }

        return if (inputRate == SR) out else resample(out, SR, inputRate)
    }

    private fun processFrame(): FloatArray {
        // ── 1. STFT ─────────────────────────────────────────────────────────
        val re = FloatArray(FFT_SIZE); val im = FloatArray(FFT_SIZE)
        for (i in 0 until FFT_SIZE) re[i] = analysisBuf[i] * window[i]
        fftArbitrary(re, im)      // Bluestein FFT — handles FFT_SIZE=960

        val specR = re.copyOf(FREQ_BINS)
        val specI = im.copyOf(FREQ_BINS)
        val specMag = FloatArray(FREQ_BINS) { k -> sqrt(specR[k] * specR[k] + specI[k] * specI[k]) }

        // ── 2. ERB log-energy features [NB_ERB] ──────────────────────────────
        val erbFeat = FloatArray(NB_ERB) { b ->
            var e = 0f
            for (f in ERB_BINS[b] until ERB_BINS[b + 1]) e += specMag[f] * specMag[f]
            ln(1f + e)
        }

        // ── 3. Run encoder ────────────────────────────────────────────────────
        // Input spec for encoder: NB_DF complex bins → [1, NB_DF, 2]
        val specDf = FloatArray(NB_DF * 2) { i ->
            if (i % 2 == 0) specR[i / 2] else specI[i / 2]
        }
        val (emb, c0, e0, e1, e2, e3) = runEncoder(specDf, erbFeat)

        // ── 4. ERB decoder → gains [NB_ERB] ──────────────────────────────────
        val erbGains = runErbDecoder(emb, e0, e1, e2, e3)

        // ── 5. DF decoder → complex coefs [NB_DF * DF_ORDER * 2] ─────────────
        val dfCoefs = runDfDecoder(emb, c0)

        // ── 6a. Apply ERB gains (magnitude suppression) ───────────────────────
        for (b in 0 until NB_ERB) {
            val g = erbGains[b].coerceIn(0f, 1f)
            for (f in ERB_BINS[b] until ERB_BINS[b + 1]) {
                specR[f] *= g; specI[f] *= g
            }
        }

        // ── 6b. DF complex FIR filter on first NB_DF bins ────────────────────
        for (f in 0 until NB_DF) {
            dfBuf[dfBufIdx][f][0] = specR[f]; dfBuf[dfBufIdx][f][1] = specI[f]
        }
        dfBufIdx = (dfBufIdx + 1) % DF_ORDER

        for (f in 0 until NB_DF) {
            var outR = 0f; var outI = 0f
            for (d in 0 until DF_ORDER) {
                val bufIdx = (dfBufIdx - 1 - d + DF_ORDER) % DF_ORDER
                val base   = (f * DF_ORDER + d) * 2
                val cR = dfCoefs[base]; val cI = dfCoefs[base + 1]
                val xR = dfBuf[bufIdx][f][0]; val xI = dfBuf[bufIdx][f][1]
                outR += cR * xR - cI * xI
                outI += cR * xI + cI * xR
            }
            specR[f] = outR; specI[f] = outI
        }

        // ── 7. iSTFT overlap-add ──────────────────────────────────────────────
        return istft(specR, specI)
    }

    // ── ONNX session calls ────────────────────────────────────────────────────

    private data class EncOut(
        val emb: FloatArray, val c0: FloatArray,
        val e0: FloatArray, val e1: FloatArray,
        val e2: FloatArray, val e3: FloatArray,
    )

    private fun runEncoder(specDf: FloatArray, erbFeat: FloatArray): EncOut {
        val s = encSess ?: return EncOut(
            FloatArray(ENC_HIDDEN), FloatArray(NB_DF * 2),
            FloatArray(0), FloatArray(0), FloatArray(0), FloatArray(0))
        val specT = tensor(specDf,  longArrayOf(1, NB_DF.toLong(), 2))
        val erbT  = tensor(erbFeat, longArrayOf(1, NB_ERB.toLong()))
        val h0T   = tensor(hEnc0,   longArrayOf(1, 1, ENC_HIDDEN.toLong()))
        val h1T   = tensor(hEnc1,   longArrayOf(1, 1, ENC_HIDDEN.toLong()))

        val inNames = s.inputNames.toList()
        // Use OnnxTensorLike (not OnnxValue) — run() requires Map<String, out OnnxTensorLike>
        val inputs = linkedMapOf<String, OnnxTensorLike>(
            inNames[0] to specT,
            inNames[1] to erbT,
            inNames[2] to h0T,
            inNames[3] to h1T,
        )
        val res = s.run(inputs)
        val outNames = s.outputNames.toList()

        // Result.get(name) returns Optional<OnnxValue> — unwrap with .get()
        val emb = floats(res.get(outNames[0]).get() as OnnxTensor)
        val c0  = if (outNames.size > 1) floats(res.get(outNames[1]).get() as OnnxTensor) else FloatArray(NB_DF * 2)
        val e0  = if (outNames.size > 2) floats(res.get(outNames[2]).get() as OnnxTensor) else FloatArray(0)
        val e1  = if (outNames.size > 3) floats(res.get(outNames[3]).get() as OnnxTensor) else FloatArray(0)
        val e2  = if (outNames.size > 4) floats(res.get(outNames[4]).get() as OnnxTensor) else FloatArray(0)
        val e3  = if (outNames.size > 5) floats(res.get(outNames[5]).get() as OnnxTensor) else FloatArray(0)
        val n = outNames.size
        if (n >= 2) hEnc0 = floats(res.get(outNames[n - 2]).get() as OnnxTensor)
        if (n >= 1) hEnc1 = floats(res.get(outNames[n - 1]).get() as OnnxTensor)

        res.close()
        listOf(specT, erbT, h0T, h1T).forEach { it.close() }
        return EncOut(emb, c0, e0, e1, e2, e3)
    }

    private fun runErbDecoder(
        emb: FloatArray, e0: FloatArray, e1: FloatArray,
        e2: FloatArray, e3: FloatArray,
    ): FloatArray {
        val s = erbDecSess ?: return FloatArray(NB_ERB) { 1f }
        val inNames = s.inputNames.toList()

        val tensors = buildList {
            add(tensor(emb,  longArrayOf(1, emb.size.toLong())))
            if (inNames.size > 1 && e3.isNotEmpty()) add(tensor(e3, longArrayOf(1, e3.size.toLong())))
            if (inNames.size > 2 && e2.isNotEmpty()) add(tensor(e2, longArrayOf(1, e2.size.toLong())))
            if (inNames.size > 3 && e1.isNotEmpty()) add(tensor(e1, longArrayOf(1, e1.size.toLong())))
            if (inNames.size > 4 && e0.isNotEmpty()) add(tensor(e0, longArrayOf(1, e0.size.toLong())))
            add(tensor(hErb0, longArrayOf(1, 1, DEC_HIDDEN.toLong())))
            add(tensor(hErb1, longArrayOf(1, 1, DEC_HIDDEN.toLong())))
        }
        val inputs: Map<String, OnnxTensorLike> = inNames.zip(tensors).take(tensors.size)
            .associate { (k, v) -> k to v }

        val res = s.run(inputs)
        val outNames = s.outputNames.toList()
        val gains = floats(res.get(outNames[0]).get() as OnnxTensor)
        val n = outNames.size
        if (n >= 2) hErb0 = floats(res.get(outNames[n - 2]).get() as OnnxTensor)
        if (n >= 1) hErb1 = floats(res.get(outNames[n - 1]).get() as OnnxTensor)

        res.close(); tensors.forEach { it.close() }
        return gains.copyOf(NB_ERB)
    }

    private fun runDfDecoder(emb: FloatArray, c0: FloatArray): FloatArray {
        val s = dfDecSess ?: return FloatArray(NB_DF * DF_ORDER * 2)
        val inNames = s.inputNames.toList()

        val embT  = tensor(emb,  longArrayOf(1, emb.size.toLong()))
        val c0T   = tensor(c0,   longArrayOf(1, c0.size.toLong()))
        val h0T   = tensor(hDf0, longArrayOf(1, 1, DEC_HIDDEN.toLong()))
        val h1T   = tensor(hDf1, longArrayOf(1, 1, DEC_HIDDEN.toLong()))

        val allT  = listOf(embT, c0T, h0T, h1T)
        val inputs: Map<String, OnnxTensorLike> = inNames.zip(allT).take(minOf(inNames.size, allT.size))
            .associate { (k, v) -> k to v }

        val res = s.run(inputs)
        val outNames = s.outputNames.toList()
        val coefs = floats(res.get(outNames[0]).get() as OnnxTensor)
        val n = outNames.size
        if (n >= 2) hDf0 = floats(res.get(outNames[n - 2]).get() as OnnxTensor)
        if (n >= 1) hDf1 = floats(res.get(outNames[n - 1]).get() as OnnxTensor)

        res.close(); allT.forEach { it.close() }
        return coefs
    }

    // ── iSTFT overlap-add ─────────────────────────────────────────────────────

    private fun istft(specR: FloatArray, specI: FloatArray): FloatArray {
        val re = FloatArray(FFT_SIZE); val im = FloatArray(FFT_SIZE)
        for (k in 0 until FREQ_BINS) { re[k] = specR[k]; im[k] = specI[k] }
        // Hermitian symmetry for negative frequencies
        for (k in 1 until FREQ_BINS - 1) {
            re[FFT_SIZE - k] =  specR[k]
            im[FFT_SIZE - k] = -specI[k]
        }
        ifftArbitrary(re, im)   // Bluestein IFFT

        // Windowed overlap-add
        for (i in 0 until FFT_SIZE) synthBuf[i] += re[i] * window[i]

        // WOLA normalisation: at each sample n, divide by w[n]² + w[n+HOP]²
        val out = FloatArray(HOP_SIZE)
        for (i in 0 until HOP_SIZE) {
            val w0 = window[i]; val w1 = window[i + HOP_SIZE]
            val norm = w0 * w0 + w1 * w1
            out[i] = if (norm > 1e-8f) synthBuf[i] / norm else 0f
        }
        System.arraycopy(synthBuf, HOP_SIZE, synthBuf, 0, FFT_SIZE - HOP_SIZE)
        synthBuf.fill(0f, FFT_SIZE - HOP_SIZE, FFT_SIZE)
        return out
    }

    // ── Bluestein FFT — handles arbitrary (non-power-of-2) sizes ─────────────

    /** In-place forward DFT for any length. */
    private fun fftArbitrary(re: FloatArray, im: FloatArray) {
        val n = re.size
        if (n and (n - 1) == 0) { radix2Fft(re, im, false); return }
        bluestein(re, im, false)
    }

    /** In-place inverse DFT (normalised by 1/n). */
    private fun ifftArbitrary(re: FloatArray, im: FloatArray) {
        val n = re.size
        if (n and (n - 1) == 0) { radix2Fft(re, im, true); return }
        bluestein(re, im, true)
        val inv = 1f / n
        for (i in re.indices) { re[i] *= inv; im[i] *= inv }
    }

    /** Bluestein's chirp-z transform — O(n log n) for any n. */
    private fun bluestein(re: FloatArray, im: FloatArray, inverse: Boolean) {
        val n   = re.size
        val sgn = if (inverse) 1.0 else -1.0
        val m   = Integer.highestOneBit(2 * n - 1) shl 1   // next pow2 ≥ 2n-1

        // Chirp: w[k] = e^{sgn·j·π·k²/n}
        val chirpR = FloatArray(n); val chirpI = FloatArray(n)
        for (k in 0 until n) {
            val ang = sgn * PI * (k.toLong() * k % (2 * n)) / n
            chirpR[k] = cos(ang).toFloat(); chirpI[k] = sin(ang).toFloat()
        }

        // a[k] = x[k] · conj(chirp[k])
        val aR = FloatArray(m); val aI = FloatArray(m)
        for (k in 0 until n) {
            aR[k] = re[k] * chirpR[k] + im[k] * chirpI[k]
            aI[k] = im[k] * chirpR[k] - re[k] * chirpI[k]
        }

        // b[k] = chirp[k] (with wrap for convolution)
        val bR = FloatArray(m); val bI = FloatArray(m)
        bR[0] = chirpR[0]; bI[0] = chirpI[0]
        for (k in 1 until n) {
            bR[k] = chirpR[k]; bI[k] = chirpI[k]
            bR[m - k] = chirpR[k]; bI[m - k] = chirpI[k]
        }

        // Convolution via radix-2 FFT
        radix2Fft(aR, aI, false); radix2Fft(bR, bI, false)
        val cR = FloatArray(m); val cI = FloatArray(m)
        for (i in 0 until m) {
            cR[i] = aR[i] * bR[i] - aI[i] * bI[i]
            cI[i] = aR[i] * bI[i] + aI[i] * bR[i]
        }
        radix2Fft(cR, cI, true)
        val norm = 1f / m
        for (i in 0 until m) { cR[i] *= norm; cI[i] *= norm }

        // Output: result[k] = conj(chirp[k]) · c[k]
        for (k in 0 until n) {
            re[k] = cR[k] * chirpR[k] + cI[k] * chirpI[k]
            im[k] = cI[k] * chirpR[k] - cR[k] * chirpI[k]
        }
    }

    /** In-place Cooley-Tukey radix-2 FFT (power-of-2 only). */
    private fun radix2Fft(re: FloatArray, im: FloatArray, inverse: Boolean) {
        val n = re.size
        // Bit-reversal
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                var t = re[i]; re[i] = re[j]; re[j] = t
                t = im[i]; im[i] = im[j]; im[j] = t
            }
        }
        // Butterfly
        val sgn = if (inverse) 1.0 else -1.0
        var len = 2
        while (len <= n) {
            val ang = sgn * 2.0 * PI / len
            val wR = cos(ang).toFloat(); val wI = sin(ang).toFloat()
            var i = 0
            while (i < n) {
                var curR = 1f; var curI = 0f
                for (k in 0 until len / 2) {
                    val u = i + k; val v = u + len / 2
                    val vR = re[v] * curR - im[v] * curI
                    val vI = re[v] * curI + im[v] * curR
                    re[v] = re[u] - vR; im[v] = im[u] - vI
                    re[u] += vR; im[u] += vI
                    val nr = curR * wR - curI * wI; curI = curR * wI + curI * wR; curR = nr
                }
                i += len
            }
            len = len shl 1
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun tensor(data: FloatArray, shape: LongArray): OnnxTensor =
        OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(data), shape)

    private fun floats(t: OnnxTensor): FloatArray {
        val buf = t.floatBuffer
        return FloatArray(buf.remaining()).also { buf.get(it) }
    }

    private fun resample(input: FloatArray, src: Int, dst: Int): FloatArray {
        if (src == dst) return input
        val ratio = dst.toDouble() / src
        return FloatArray((input.size * ratio).roundToInt()) { i ->
            val pos = i / ratio; val idx = pos.toInt(); val frac = (pos - idx).toFloat()
            if (idx + 1 < input.size) input[idx] * (1f - frac) + input[idx + 1] * frac
            else input.getOrElse(idx) { 0f }
        }
    }

    fun close() {
        encSess?.close(); erbDecSess?.close(); dfDecSess?.close(); ortEnv.close()
    }
}
