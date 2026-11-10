import 'dart:typed_data';

import 'package:icicles_generators/icicles_generators.dart';
import 'package:test/test.dart';

AudioFrame frameWithBand(int band, [double value = 1]) {
  final row = Float32List(AudioFeatureKey.columnCount);
  row[AudioFeatureKey.band(band).index] = value;
  row[AudioFeatureKey.level.index] = 0.3;
  row[AudioFeatureKey.onset.index] = 0.7;
  return AudioFeatures(row).sampleAt(Duration.zero);
}

ParamValues valuesOf(List<ParamSpec> specs, Map<String, Object> overrides) =>
    ParamValues({for (final s in specs) s.id: _defaultOf(s), ...overrides});

Object _defaultOf(ParamSpec spec) => switch (spec) {
      NumberParam(:final defaultValue) => defaultValue,
      IntParam(:final defaultValue) => defaultValue,
      BoolParam(:final defaultValue) => defaultValue,
      ChoiceParam(:final defaultValue) => defaultValue,
      TextParam(:final defaultValue) => defaultValue,
      ColorParam(:final defaultValue) => defaultValue,
      PaletteParam(:final defaultValue) => defaultValue,
    };

void main() {
  group('AudioRangePreset', () {
    test('has the LedFx-like bounds and en + pl labels', () {
      expect(AudioRangePreset.full.lowHz, 20);
      expect(AudioRangePreset.full.highHz, 16000);
      expect((AudioRangePreset.lows.lowHz, AudioRangePreset.lows.highHz), (20, 250));
      expect((AudioRangePreset.lowMids.lowHz, AudioRangePreset.lowMids.highHz), (250, 500));
      expect((AudioRangePreset.mids.lowHz, AudioRangePreset.mids.highHz), (500, 2000));
      expect((AudioRangePreset.highMids.lowHz, AudioRangePreset.highMids.highHz), (2000, 4000));
      expect((AudioRangePreset.highs.lowHz, AudioRangePreset.highs.highHz), (4000, 16000));
      for (final preset in AudioRangePreset.values) {
        expect(preset.label.pl, isNotNull, reason: preset.name);
        expect(preset.option.id, preset.id);
        expect(AudioRangePreset.fromId(preset.id), preset);
      }
      expect(AudioRangePreset.fromId('nope'), AudioRangePreset.full);
      expect(AudioRangePreset.values.map((p) => p.id).toSet(), hasLength(AudioRangePreset.values.length));
    });

    test('every preset covers at least one band center, and they tile the spectrum', () {
      final centers = AudioFeatureExtractor.bandCenters;
      for (final preset in AudioRangePreset.values) {
        expect(centers.any((c) => c >= preset.lowHz && c <= preset.highHz), isTrue, reason: preset.name);
      }
      const ladder = [
        AudioRangePreset.lows,
        AudioRangePreset.lowMids,
        AudioRangePreset.mids,
        AudioRangePreset.highMids,
        AudioRangePreset.highs,
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(ladder[i].lowHz, ladder[i - 1].highHz);
      }
    });
  });

  group('audioRangeParams', () {
    final specs = audioRangeParams();

    test('are a choice and two custom-only log Hz numbers', () {
      expect(specs.map((s) => s.id), ['range', 'rangeLowHz', 'rangeHighHz']);
      final choice = specs[0] as ChoiceParam;
      expect(choice.defaultValue, 'lows');
      expect(choice.options.map((o) => o.id), AudioRangePreset.values.map((p) => p.id));
      for (final spec in specs.skip(1).cast<NumberParam>()) {
        expect(spec.min, audioRangeMinHz);
        expect(spec.max, audioRangeMaxHz);
        expect(spec.scale, NumberScale.log);
        expect(spec.unit, 'Hz');
        expect(spec.description?.pl, isNotNull);
      }
      expect((specs[1] as NumberParam).defaultValue, 20);
      expect((specs[2] as NumberParam).defaultValue, 250);
      final custom = audioRangeParams(prefix: 'zoom', defaultPreset: AudioRangePreset.custom);
      expect(custom.map((s) => s.id), ['zoom', 'zoomLowHz', 'zoomHighHz']);
      expect((custom[1] as NumberParam).defaultValue, 20);
      expect((custom[2] as NumberParam).defaultValue, 16000);
    });

    test('audioRangeValue follows the preset, the custom pair swapped if reversed', () {
      final lows = frameWithBand(0);
      final highs = frameWithBand(15);
      expect(audioRangeValue(valuesOf(specs, {}), lows), 1);
      expect(audioRangeValue(valuesOf(specs, {}), highs), 0);
      expect(audioRangeValue(valuesOf(specs, {'range': 'highs'}), highs), closeTo(1 / 6, 1e-6));
      expect(audioRangeValue(valuesOf(specs, {'range': 'full'}), highs), closeTo(1 / 16, 1e-6));
      final custom = valuesOf(specs, {'range': 'custom', 'rangeLowHz': 16000.0, 'rangeHighHz': 10000.0});
      expect(audioRangeValue(custom, highs), closeTo(1 / 2, 1e-6)); // centers 10874 and 13203 Hz
      expect(audioRangeValue(custom, lows), 0);
      // The Hz pair is ignored unless the preset is custom.
      expect(audioRangeValue(valuesOf(specs, {'rangeLowHz': 16000.0, 'rangeHighHz': 10000.0}), lows), 1);
      final range = audioRangeOf(custom);
      expect(range.lowHz, 10000);
      expect(range.highHz, 16000);
    });

    test('AudioRange maps a position across its bounds on the mel scale', () {
      final full = AudioRange.ofPreset(AudioRangePreset.full);
      expect(full.frequencyAt(0), closeTo(20, 1e-6));
      expect(full.frequencyAt(1), closeTo(16000, 1e-6));
      expect(full.frequencyAt(0.5), lessThan(8010)); // mel: the middle sits well below the linear midpoint
      expect(full.frequencyAt(0.5), greaterThan(1000));
      final zoom = AudioRange(4000, 16000);
      final highs = frameWithBand(15);
      expect(zoom.spectrumAt(highs, 1), 1);
      expect(zoom.spectrumAt(highs, 0), lessThan(0.05));
      expect(AudioRange(1, 1e9).lowHz, audioRangeMinHz);
      expect(AudioRange(1, 1e9).highHz, audioRangeMaxHz);
    });
  });

  group('audioSourceParam', () {
    final specs = [audioSourceParam(), ...audioRangeParams()];

    test('offers level, range, onset and the beat pulse', () {
      final spec = specs[0] as ChoiceParam;
      expect(spec.id, 'source');
      expect(spec.defaultValue, 'range');
      expect(spec.options.map((o) => o.id), ['level', 'range', 'onset', 'beat']);
      for (final option in spec.options) {
        expect(option.label.pl, isNotNull);
      }
    });

    test('audioSourceValue reads the chosen source', () {
      final frame = frameWithBand(0);
      expect(audioSourceValue(valuesOf(specs, {}), frame), 1);
      expect(audioSourceValue(valuesOf(specs, {'source': 'level'}), frame), closeTo(0.3, 1e-6));
      expect(audioSourceValue(valuesOf(specs, {'source': 'onset'}), frame), closeTo(0.7, 1e-6));
      expect(audioSourceValue(valuesOf(specs, {'source': 'beat'}), frame), 0);
      expect(audioSourceValue(valuesOf(specs, {'source': 'nope'}), frame), 1);
    });
  });
}
