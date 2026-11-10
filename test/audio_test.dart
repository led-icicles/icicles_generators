import 'dart:math' as math;
import 'dart:typed_data';

import 'package:icicles_generators/icicles_generators.dart';
import 'package:test/test.dart';

Float32List sine(double frequency, {int sampleRate = 44100, double seconds = 2, double amplitude = 0.5}) =>
    Float32List.fromList([
      for (var i = 0; i < sampleRate * seconds; i++) amplitude * math.sin(2 * math.pi * frequency * i / sampleRate),
    ]);

/// Short noise bursts every [period] seconds, silence between.
Float32List clicks({int sampleRate = 44100, double seconds = 3, double period = 0.5}) {
  final out = Float32List((sampleRate * seconds).round());
  final random = math.Random(1);
  for (var t = 0.25; t < seconds; t += period) {
    final start = (t * sampleRate).round();
    for (var i = 0; i < sampleRate ~/ 200 && start + i < out.length; i++) {
      out[start + i] = (random.nextDouble() * 2 - 1) * math.exp(-i / (sampleRate / 1000));
    }
  }
  return out;
}

int loudestBand(AudioFrame frame) {
  var best = 0;
  for (var b = 1; b < 16; b++) {
    if (frame.band(b) > frame.band(best)) best = b;
  }
  return best;
}

int nearestBand(double frequency) {
  double mel(double f) => 2595 * math.log(1 + f / 700) / math.ln10;
  final centers = AudioFeatureExtractor.bandCenters;
  var best = 0;
  for (var b = 1; b < centers.length; b++) {
    if ((mel(centers[b]) - mel(frequency)).abs() < (mel(centers[best]) - mel(frequency)).abs()) best = b;
  }
  return best;
}

void main() {
  group('AudioFeatureExtractor', () {
    test('window size scales with the sample rate', () {
      expect(AudioFeatureExtractor.windowSizeFor(44100), 2048);
      expect(AudioFeatureExtractor.windowSizeFor(48000), 2048);
      expect(AudioFeatureExtractor.windowSizeFor(22050), 1024);
      expect(AudioFeatureExtractor.windowSizeFor(96000), 4096);
      expect(AudioFeatureExtractor.windowSizeFor(8000), 512);
    });

    test('a 100 Hz sine is bass, not treble', () {
      final features = AudioFeatureExtractor.extract(sine(100), 44100);
      expect(features.frameCount, 200);
      expect(features.hopDuration, const Duration(milliseconds: 10));
      final frame = features.sampleAt(const Duration(seconds: 1));
      expect(frame.bass, greaterThan(0.9));
      expect(frame.treble, lessThan(0.05));
      expect(frame.mid, lessThan(0.6));
      expect(frame.level, greaterThan(0.9));
      expect(frame.peakFrequency, closeTo((math.log(100) - math.log(40)) / (math.log(16000) - math.log(40)), 0.03));
    });

    for (final rate in [8000, 22050, 44100, 48000, 96000]) {
      test('the right mel band peaks at $rate Hz', () {
        for (final frequency in [150.0, 1000.0, 3000.0]) {
          if (frequency * 2 >= rate) continue;
          final features = AudioFeatureExtractor.extract(sine(frequency, sampleRate: rate, seconds: 1), rate);
          final frame = features.sampleAt(const Duration(milliseconds: 500));
          expect(loudestBand(frame), nearestBand(frequency), reason: '$frequency Hz');
        }
      });
    }

    test('a click train gives onset peaks on the clicks', () {
      final features = AudioFeatureExtractor.extract(clicks(), 44100);
      final onset = features.column(AudioFeatureKey.onset);
      for (var t = 0.25; t < 3; t += 0.5) {
        final row = (t * 100).round();
        final near = [for (var r = row - 3; r <= row + 3; r++) onset[r]].reduce(math.max);
        expect(near, greaterThan(0.5), reason: 'click at $t s');
        final between =
            [for (var r = row + 10; r <= math.min(row + 40, onset.length - 1); r++) onset[r]].reduce(math.max);
        expect(between, lessThan(0.1), reason: 'after the click at $t s');
      }
    });

    test('silence gives zeros', () {
      final features = AudioFeatureExtractor.extract(Float32List(44100), 44100);
      expect(features.frameCount, 100);
      for (final key in AudioFeatureKey.values.where((k) => k.isColumn)) {
        expect(features.column(key), everyElement(0), reason: key.name);
      }
    });

    test('chunked input gives the same features', () {
      final samples = clicks(seconds: 1);
      final whole = AudioFeatureExtractor.extract(samples, 44100);
      final extractor = AudioFeatureExtractor(44100);
      for (var start = 0; start < samples.length; start += 777) {
        extractor.add(Float32List.sublistView(samples, start, math.min(samples.length, start + 777)));
      }
      final chunked = extractor.finish();
      expect(chunked.toBytes(), whole.toBytes());
      expect(chunked.contentHash, whole.contentHash);
    });
  });

  group('AudioFeatures', () {
    final data = Float32List(3 * AudioFeatureKey.columnCount);
    data[AudioFeatureKey.bass.index] = 0.2;
    data[AudioFeatureKey.columnCount + AudioFeatureKey.bass.index] = 0.6;
    data[2 * AudioFeatureKey.columnCount + AudioFeatureKey.bass.index] = 2.0; // clamped
    final features = AudioFeatures(data);

    test('interpolates between rows and is silent outside the song', () {
      expect(features.duration, const Duration(milliseconds: 30));
      expect(features.sampleAt(const Duration(milliseconds: 5)).bass, closeTo(0.4, 1e-6));
      expect(features.sampleAt(const Duration(milliseconds: 25)).bass, closeTo(1.0, 1e-6));
      expect(features.sampleAt(const Duration(milliseconds: 30)).bass, 0);
      expect(features.sampleAt(const Duration(milliseconds: -1)).bass, 0);
      expect(features.value(2, AudioFeatureKey.bass), 1.0);
    });

    test('adds the beat fields of a tempo', () {
      final frame = features.sampleAt(const Duration(milliseconds: 750), tempo: Tempo(bpm: 60));
      expect(frame.bass, 0);
      expect(frame.beatPhase, closeTo(0.75, 1e-9));
      expect(frame.beatIndex, 0);
      expect(frame[AudioFeatureKey.barPhase], closeTo(0.75 / 4, 1e-9));
    });

    test('round-trips through bytes, with a stable content hash', () {
      final decoded = AudioFeatures.fromBytes(features.toBytes());
      expect(decoded.toBytes(), features.toBytes());
      expect(decoded.contentHash, features.contentHash);
      expect(features.contentHash, matches(RegExp(r'^fnv1a64:[0-9a-f]{16}$')));
      // Known FNV-1a 64 vectors (exact on the VM and under dart2js).
      expect(fnv1a64Hex(const []), 'cbf29ce484222325');
      expect(fnv1a64Hex('a'.codeUnits), 'af63dc4c8601ec8c');
      expect(fnv1a64Hex('foobar'.codeUnits), '85944171f73967e8');
      final other = Float32List.fromList(data)..[0] = 0.5;
      expect(AudioFeatures(other).contentHash, isNot(features.contentHash));
      expect(() => AudioFeatures.fromBytes(Uint8List(3)), throwsFormatException);
    });

    test('energyBetween averages the bands whose centers fall in the range', () {
      final centers = AudioFeatureExtractor.bandCenters;
      for (var hot = 0; hot < AudioFeatureKey.bandCount; hot++) {
        final row = Float32List(AudioFeatureKey.columnCount);
        row[AudioFeatureKey.band(hot).index] = 1;
        final frame = AudioFeatures(row).sampleAt(Duration.zero);
        for (final preset in AudioRangePreset.values) {
          final inside = [for (final c in centers) c >= preset.lowHz && c <= preset.highHz];
          final count = inside.where((b) => b).length;
          final expected = inside[hot] ? 1 / count : 0.0;
          expect(frame.energyBetween(preset.lowHz, preset.highHz), closeTo(expected, 1e-6),
              reason: 'band $hot in ${preset.name}');
        }
        // Reversed bounds are the same range.
        expect(frame.energyBetween(16000, 20), closeTo(1 / 16, 1e-6));
      }
    });

    test('energyBetween interpolates a range narrower than a band', () {
      final row = Float32List(AudioFeatureKey.columnCount);
      row[AudioFeatureKey.band(0).index] = 1;
      final frame = AudioFeatures(row).sampleAt(Duration.zero);
      final centers = AudioFeatureExtractor.bandCenters;
      expect(frame.energyBetween(centers[0] - 1, centers[0] + 1), 1);
      // Between band 0 (hot) and band 1 (silent): partway down.
      final between = frame.energyBetween(centers[0] + 20, centers[0] + 40);
      expect(between, greaterThan(0.5));
      expect(between, lessThan(1));
      // Far above every center: the highest band.
      expect(frame.energyBetween(15000, 15500), 0);
      expect(frame.bandAtHz(centers[0]), 1);
      expect(frame.bandAtHz(centers[1]), closeTo(0, 1e-6));
      expect(frame.bandAtHz(1), 1);
      expect(frame.bandAtHz(double.nan), 0);
      expect(frame.energyBetween(double.infinity, 20), 0);
      expect(AudioFrame.silent.energyBetween(20, 16000), 0);
    });

    test('bandAt interpolates the spectrum', () {
      final row = Float32List(AudioFeatureKey.columnCount);
      row[AudioFeatureKey.band(0).index] = 1;
      final frame = AudioFeatures(row).sampleAt(Duration.zero);
      expect(frame.bandAt(0), 1);
      expect(frame.bandAt(0.5 / 15), closeTo(0.5, 1e-6));
      expect(frame.bands, hasLength(16));
    });
  });
}
