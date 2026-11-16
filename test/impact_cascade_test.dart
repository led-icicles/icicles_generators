import 'dart:typed_data';

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Every frame's RGB bytes of [generator] for [request].
List<Uint8List> frames(Generator generator, BakeRequest request) {
  final out = <Uint8List>[];
  renderGeneratorFrames(generator, request, (_, __, rgb) => out.add(Uint8List.fromList(rgb)));
  return out;
}

int sum(Uint8List rgb, [int from = 0, int? to]) {
  var s = 0;
  for (var i = from; i < (to ?? rgb.length); i++) {
    s += rgb[i];
  }
  return s;
}

/// The brightness (red channel) of icicle pixel ([x], [y]).
int red(Uint8List rgb, int x, int y) => rgb[(x * testSetup.yCount + y) * 3];

BakeRequest request(Map<String, ParamBinding> bindings, {double seconds = 2}) => BakeRequest.forLength(
    setup: testSetup, length: Duration(milliseconds: (seconds * 1000).round()), bindings: bindings);

void main() {
  const impact = ImpactGenerator();

  group('Impact', () {
    test('fires once at the clip start and fades', () {
      final f = frames(impact, request({'shape': const ConstantBinding('full'), 'travel': const ConstantBinding(0.0)}));
      expect(red(f[0], 0, 0), 255);
      expect(sum(f[3]), lessThan(sum(f[0])));
      expect(sum(f[59]), 0);
    });

    test('exp and linear fades differ, a cut-off holds until the end', () {
      Map<String, ParamBinding> fade(String curve) => {
            'shape': const ConstantBinding('full'),
            'travel': const ConstantBinding(0.0),
            'curve': ConstantBinding(curve),
            'decay': const ConstantBinding(1.0),
          };
      final exp = frames(impact, request(fade('exp')));
      final linear = frames(impact, request(fade('linear')));
      final hold = frames(impact, request(fade('hold')));
      // Half way (15 frames = 0.5 s): exp is far darker than linear.
      expect(red(exp[15], 0, 0), lessThan(red(linear[15], 0, 0)));
      expect(red(linear[15], 0, 0), closeTo(128, 3));
      expect(red(hold[28], 0, 0), 255);
      expect(red(hold[31], 0, 0), 0);
    });

    test('a center ring reaches the edge after the travel time', () {
      final f =
          frames(impact, request({'shape': const ConstantBinding('center'), 'travel': const ConstantBinding(1.0)}));
      const x = 11, y = 9; // near the middle of 24×20
      expect(red(f[3], x, y), greaterThan(0));
      expect(red(f[3], 0, 0), 0, reason: 'the corner is not reached yet');
      expect(red(f[33], 0, 0), greaterThan(0));
    });

    test('tips rise before the roots', () {
      final f = frames(impact, request({'shape': const ConstantBinding('tips'), 'travel': const ConstantBinding(1.0)}));
      expect(red(f[6], 5, testSetup.yCount - 1), greaterThan(0));
      expect(red(f[6], 5, 0), 0);
    });

    test('repeating triggers keep to 3 hits a second', () {
      // A cue every 100 ms.
      final cues = CueHits([for (var i = 0; i < 20; i++) CueHit(Duration(milliseconds: 100 * i), 1)]);
      final f = <Uint8List>[];
      renderGeneratorFrames(
        impact,
        BakeRequest.forLength(
          setup: testSetup,
          length: const Duration(seconds: 2),
          bindings: {
            'trigger': const ConstantBinding('cues'),
            'shape': const ConstantBinding('full'),
            'travel': const ConstantBinding(0.0),
            'curve': const ConstantBinding('hold'),
            'decay': const ConstantBinding(0.05),
          },
          cues: cues,
        ),
        (_, __, rgb) => f.add(Uint8List.fromList(rgb)),
      );
      var hits = 0;
      for (var i = 0; i < f.length; i++) {
        final on = red(f[i], 0, 0) > 0;
        final before = i > 0 && red(f[i - 1], 0, 0) > 0;
        if (on && !before) hits++;
      }
      expect(hits, inInclusiveRange(5, 6), reason: '2 s at ≥ 335 ms apart');
    });
  });

  group('Cascade', () {
    // Input: icicle x is lit only on frame 10 (a single flash).
    List<AnimationView> flashInputs(BakeRequest r) => [
          for (var i = 0; i < r.frameCount; i++)
            FrameCodec.decodeView(
              testSetup,
              Uint8List.fromList(List.filled(testSetup.frameBytes, i == 10 ? 200 : 0)),
              duration: testSetup.framerate.frameDuration(i),
            ),
        ];

    List<AnimationView> run(Map<String, ParamBinding> bindings) {
      final r = request(bindings);
      final runner = EffectRunner(const CascadeEffect(), r);
      final inputs = flashInputs(r);
      return [for (var i = 0; i < inputs.length; i++) runner.applyAt(i, inputs[i])];
    }

    int lit(AnimationView v, int x) => v.frame.pixels[x * testSetup.yCount].red;

    test('the flash reaches icicle x after x steps', () {
      // 1 frame per step at 30 fps.
      final out = run({'delay': const ConstantBinding(1 / 30)});
      for (var x = 0; x < 5; x++) {
        expect(lit(out[10 + x], x), 200, reason: 'icicle $x');
        expect(lit(out[10 + x], x + 1), 0);
      }
    });

    test('from the center is symmetric, a zero delay passes through', () {
      final out = run({'delay': const ConstantBinding(1 / 30), 'direction': const ConstantBinding('fromCenter')});
      for (var x = 0; x < testSetup.xCount; x++) {
        final mirror = testSetup.xCount - 1 - x;
        for (var i = 0; i < out.length; i++) {
          expect(lit(out[i], x), lit(out[i], mirror), reason: 'frame $i icicle $x');
        }
      }
      final pass = run({'delay': const ConstantBinding(0.0)});
      expect(lit(pass[10], 23), 200);
      expect(lit(pass[11], 23), 0);
    });

    test('a lagging icicle is black before its history exists', () {
      final r = request({'delay': const ConstantBinding(1 / 30)});
      final runner = EffectRunner(const CascadeEffect(), r);
      final white = FrameCodec.decodeView(testSetup, Uint8List.fromList(List.filled(testSetup.frameBytes, 255)),
          duration: testSetup.framerate.frameDuration(0));
      final first = runner.applyAt(0, white);
      expect(lit(first, 0), 255);
      expect(lit(first, 1), 0);
    });

    test('panels are the steps after the last icicle', () {
      final offsets = cascadeOffsets(
        xCount: 4,
        panelsCount: 2,
        direction: CascadeDirection.leftToRight,
        curve: CascadeCurve.linear,
        panels: CascadePanels.after,
        seed: 1,
      );
      expect(offsets.icicles, [0, 0.2, 0.4, 0.6]);
      expect(offsets.panels, [0.8, 1]);
    });
  });
}
