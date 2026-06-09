import 'dart:math';
import 'dart:typed_data';

class FFTService {
  static Float64List hannWindow(int n) {
    final w = Float64List(n);
    for (int i = 0; i < n; i++) {
      w[i] = 0.5 * (1.0 - cos(2.0 * pi * i / n));
    }
    return w;
  }

  // In-place Cooley-Tukey radix-2 DIT FFT.
  // Requires re.length == im.length == power-of-2.
  static void fft(Float64List re, Float64List im) {
    final int n = re.length;

    // Bit-reversal permutation
    for (int i = 1, j = 0; i < n; i++) {
      int bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        double t = re[i]; re[i] = re[j]; re[j] = t;
        t = im[i]; im[i] = im[j]; im[j] = t;
      }
    }

    // Butterfly stages
    for (int len = 2; len <= n; len <<= 1) {
      final double ang = -2.0 * pi / len;
      final double wR = cos(ang);
      final double wI = sin(ang);
      for (int i = 0; i < n; i += len) {
        double curR = 1.0, curI = 0.0;
        final int half = len >> 1;
        for (int j = 0; j < half; j++) {
          final int u = i + j;
          final int v = u + half;
          final double vR = re[v] * curR - im[v] * curI;
          final double vI = re[v] * curI + im[v] * curR;
          re[v] = re[u] - vR;
          im[v] = im[u] - vI;
          re[u] += vR;
          im[u] += vI;
          final double nr = curR * wR - curI * wI;
          curI = curR * wI + curI * wR;
          curR = nr;
        }
      }
    }
  }

  // In-place IFFT via conjugate trick.
  static void ifft(Float64List re, Float64List im) {
    final int n = re.length;
    for (int i = 0; i < n; i++) im[i] = -im[i];
    fft(re, im);
    for (int i = 0; i < n; i++) {
      re[i] /= n;
      im[i] = -im[i] / n;
    }
  }

  // Wraps x to [-π, π].
  static double princArg(double x) {
    return x - 2.0 * pi * (x / (2.0 * pi)).roundToDouble();
  }

  static double lerp(double a, double b, double t) => a + (b - a) * t;

  // Nearest power-of-2 >= n
  static int nextPow2(int n) {
    int p = 1;
    while (p < n) p <<= 1;
    return p;
  }
}
