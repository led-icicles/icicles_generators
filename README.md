# icicles_generators

Parametric, audio-reactive generators and effects for [icicles](https://github.com/led-icicles) animations.

A **generator** is an animation written as code: a function called once per frame that draws through the
`Icicles` API of `icicles_animation_dart`. Its inputs are the time, user parameters (described by a schema, so
the host can build the UI) and features of the music. A generator clip is **baked** into an ordinary
`Animation` on the frame grid, so it previews, seeks and exports exactly like an `.anim` file.

- `package:icicles_generators/icicles_generators.dart` — pure Dart (no Flutter, no `dart:io`): the contracts,
  parameters and bindings, audio features and their extractor, the baker, the effect runner, helpers, built-in
  generators and effects.
- `package:icicles_generators/plugin.dart` — the out-of-process plugin protocol (uses `dart:io`): for plugins
  and for the host's data layer.

## Writing a generator

```dart
import 'dart:math' as math;

import 'package:icicles_animation_dart/icicles_animation_dart.dart';
import 'package:icicles_generators/icicles_generators.dart';

final class PulseGenerator implements Generator {
  const PulseGenerator();

  @override
  GeneratorInfo get info => const GeneratorInfo(
        id: 'my.plugin/pulse', // unique; built-ins use `icicles.<name>`
        version: 1, // bump when the same parameters render differently
        name: LocalizedText('Pulse', pl: 'Puls'),
        description: LocalizedText('Breathing color.', pl: 'Oddychający kolor.'),
        category: GeneratorCategory.basic,
      );

  @override
  List<ParamSpec> get params => const [
        ColorParam(id: 'color', label: LocalizedText('Color', pl: 'Kolor'), defaultValue: Color(0xFFFF0040)),
        NumberParam(
          id: 'rate',
          label: LocalizedText('Rate', pl: 'Tempo'),
          min: 0.1,
          max: 4,
          defaultValue: 1,
          scale: NumberScale.log,
          unit: '/s',
        ),
        panelModeParam,
      ];

  @override
  GeneratorInstance create(GeneratorSetup setup) => _Pulse();
}

final class _Pulse implements GeneratorInstance {
  @override
  void render(FrameContext ctx, Icicles out) {
    final v = 0.5 + 0.5 * math.sin(ctx.seconds * ctx.params.number('rate') * 2 * math.pi);
    out.setAllPixelsColor(dim(ctx.params.color('color'), v));
    applyPanelMode(out, panelModeOf(ctx.params));
  }
}
```

Rules:

- `Generator` classes are stateless (ideally `const`); all state lives in the `GeneratorInstance` that `create`
  returns for one bake.
- `render` is called once per grid frame **in order from frame 0**, so instances may keep state (particles,
  followers). `out` keeps the previous frame; whatever you don't draw stays as it was.
- Use only `ctx.random` (seeded from `GeneratorSetup.seed`) or noise seeded from `setup.seed`, so a bake is
  reproducible: the same request gives the same bytes, in process or in a plugin.
- Stay layout-independent: read `ctx.xCount`/`ctx.yCount`, use `ctx.nx(x)`/`ctx.ny(y)` (0..1). Pixels are
  column-major (`x` = icicle, `y` = LED from the top, `y = 0` at the roof).

### `FrameContext`

| Field | Meaning |
|---|---|
| `frameIndex`, `time`, `delta`, `seconds`, `deltaSeconds` | frame `i` starts at `framerate.frameStart(i)` (generator time, 0 at the clip's source start) |
| `params` | `ParamValues` resolved at this frame: `number(id)`, `integer`, `flag`, `choice`, `color`, `palette` |
| `audio` | `AudioFrame`: `level`, `bass`, `mid`, `treble`, `onset`, `peakFrequency`, `bands`/`band(i)`/`bandAt(t)`/`bandAtHz(hz)` (16 mel bands), `energyBetween(lowHz, highHz)`, `beatPhase`, `barPhase`, `beatPulse`, `beatIndex`, `bpm` — all 0 without a soundtrack/tempo |
| `random` | the bake's seeded `Random` |
| `setup` | `xCount`, `yCount`, `radioPanelsCount`, `radioPanelPixelCount`, `framerate`, `seed` |

Set `GeneratorInfo.usesAudio` when the generator reads `ctx.audio` (including the beat fields); otherwise the
baker passes silence (the beat fields still follow the tempo), so a bake never depends on audio it doesn't
declare.

### Parameter schema

`ParamSpec` is sealed: `NumberParam` (min, max, default, step, `scale: linear|log`, unit), `IntParam`,
`BoolParam`, `ChoiceParam` (options with labels), `TextParam` (a free string of at most `maxLength` characters;
read with `params.text(id)`), `ColorParam`, `PaletteParam` (presets in `Palette.presets`: rainbow, ice, fire,
ocean, aurora, party). Labels are `LocalizedText(en, pl:)`; the host picks the language.
Standard parameters: `panelModeParam` / `panelModeParamWithOwn` (radio panels off / mirror the icicles / own
drawing) with `applyPanelMode`, and `directionParam(id:, options:, defaultValue:)` — a `ChoiceParam` preset over
the `Direction` enum (`up`, `down`, `left`, `right`, `in`, `out`; `down` = towards the tips) read with
`directionOf(params)`. Helpers: `hsv(h, s, v)` (hue in turns), `dim`, `mixColors`, `addColors`,
`Palette.sample`, `SimplexNoise(seed).simplex2/simplex3`, `Font3x5` (a 3×5 bitmap font: ASCII 32–90, `_`, `♥`;
lowercase and Polish letters map to capitals).

Stored values are **salvaged** against the schema (`ParamSpec.salvage`, `salvageBindings`): unknown ids are
dropped, missing or mistyped ones fall back to the default, numbers are clamped — so projects survive generator
updates. Keep parameter ids stable.

### Bindings (modulation)

Every parameter has a `ParamBinding` (sealed); number and integer parameters can be modulated:

- `ConstantBinding(value)`
- `AudioBinding(feature, min, max, attack, release, curve, invert)` — a one-pole follower over an
  `AudioFeatureKey` (level, bass, mid, treble, onset, peakFrequency, band0…band15, beatPulse, beatPhase,
  barPhase), shaped by `pow(v, curve)`, mapped to min..max; `min` without audio.
- `BeatBinding(shape: pulse|saw|sine|square, periodBeats ¼…16, phase, min, max)` — an LFO on the tempo; `min`
  without one.
- `RampBinding(from, to, curve)` — from the first to the last frame, eased by a `RampCurve` (the library's
  `Curves`).
- `KeyframeBinding(keys, timeBase: seconds|beats, loop)` — keyframes: each `Keyframe(at, value, easing)` holds a
  `num` (number/integer parameters) or a `Color` (color parameters — these interpolate in HSV along the shorter
  hue path) at clip time `at`; between two keys the *first* key's `Easing` interpolates (Premiere style:
  `Easing.hold | linear | easeIn | easeOut | easeInOut` — the presets are the library's cubic curves — or
  `Easing.bezier(x1, y1, x2, y2)`, a CSS `cubic-bezier`), before the first key the first value, after the last the
  last value, or with `loop` the keys repeat over `last.at − first.at`. `KeyTime.beats` counts clip-local beats
  (`seconds × bpm / 60` at the tempo's BPM; 120 BPM without a tempo — the tempo's grid offset does not move
  clip-local keys).
- `RandomBinding(mode: perBeat|perBar|perTime|perFrame, interval, min, max, smooth, seed)` — sample-and-hold: a
  new uniform value in min..max on every beat / 4-beat bar of the song's beat grid (120 BPM on clip time without a
  tempo), every `interval` of clip time or every frame; deterministic from `seed` (the setup's seed when `null`)
  and the index of the hold, so a bake always repeats (`uniformHash(seed, index)` is the draw). `smooth` (0..1)
  glides between holds with a one-pole follower whose time constant is `smooth × hold length`.
- `StepBinding(steps, stepsPerBar, min, max, smooth, gate)` — a step sequencer: 2…64 levels (0..1) played
  `stepsPerBar` (1…64, default 16) per bar of the beat grid (120 BPM without a tempo), cycling (a 3-step pattern
  over 4 steps per bar does not realign on the bar); each level maps to min..max, is held for `gate` (0..1) of the
  step and then drops to `min`; `smooth` slides linearly from each step to the next.
- `EnvelopeBinding(trigger, attack, decay, sustain, release, sustainLevel, min, max, retrigger)` — an AHDSR
  envelope fired by an `EnvelopeTrigger`: `.beat`, `.bar` (the beat grid; 120 BPM without a tempo),
  `.onset(threshold)` or `.rangeHit(lowHz, highHz, threshold)` (the onset feature / the energy of a frequency range
  rising through the threshold; never without audio). The level rises 0 → 1 over `attack`, falls to `sustainLevel`
  over `decay`, holds for `sustain`, falls to 0 over `release` (durations ≤ 30 s), and the value is
  `min + (max − min) · level`. A trigger while the envelope runs restarts the attack from the current level with
  `retrigger` (the default) and is ignored otherwise.
- `MacroBinding(macroId)` — the value of a composition macro, see [Macros](#macros).
- `StackedBinding(base, modulators)` — modulator stacking, see below.

`ParamBindingJson` encodes them (`{"type": "constant" | "audio" | "beat" | "ramp" | "keyframes" | "random" |
"steps" | "envelope" | "stack" | "macro", …}`), self-describing so a project can be read without the generator. A
choice and a text are both stored as `{"type": "constant", "value": "…"}`; the parameter's spec tells them apart
when it salvages the binding.

```json
{"type": "keyframes", "timeBase": "seconds", "loop": false,
 "keys": [{"at": 0.0, "value": 0.2, "easing": "easeInOut"},
          {"at": 2.0, "value": 1.0, "easing": {"bezier": [0.42, 0.0, 0.58, 1.0]}},
          {"at": 3.0, "color": "#ff8800", "easing": "hold"}]}
{"type": "random", "mode": "perBeat", "intervalMs": 500, "min": 0.0, "max": 1.0, "smooth": 0.0, "seed": 7}
{"type": "steps", "steps": [1.0, 0.0, 0.5, 0.0], "stepsPerBar": 16, "min": 0.0, "max": 1.0, "smooth": false, "gate": 1.0}
{"type": "envelope", "trigger": "onset", "threshold": 0.5, "attackMs": 10, "decayMs": 100, "sustainMs": 0,
 "releaseMs": 300, "sustainLevel": 0.5, "min": 0.0, "max": 1.0, "retrigger": true}
{"type": "envelope", "trigger": "rangeHit", "lowHz": 20, "highHz": 250, "threshold": 0.6, …}
{"type": "stack", "base": {…}, "modulators": [{"source": {…}, "depth": 0.5, "mode": "add", "depthBinding": {…}}]}
{"type": "macro", "macro": "intensity"}
```

Decoding is lenient (unknown fields ignored, defaults filled in, an unreadable binding dropped so the parameter
falls back to its default) and salvage clamps every field: key times ≥ 0 and sorted (stable, so of two keys at the
same time the later one wins), keys of the wrong type dropped (a keyframe binding without a usable key falls back
to the default), `smooth`/`gate`/levels/thresholds to 0..1, step counts to 2…64, stages to 30 s, Bézier `x` to
0..1 and `y` to −1..2, `depth` to −1..1, at most 8 modulators, nested stacks dropped.

#### Modulator stacking

A `StackedBinding(base, modulators)` is a base binding plus any number of `Modulator(source, depth, mode,
depthBinding)` layers (Bitwig style). Per frame, the base is evaluated, then every modulator in order:

1. `source` (any binding but a stack) is evaluated to its own value and **normalized to `norm ∈ 0..1`** across
   its own range — `min..max` of an audio, beat, random, step or envelope binding, `from..to` of a ramp — or
   across the parameter's range for a constant, keyframe or macro source;
2. `depth` is `−1..1` of the parameter's range (`range = max − min` of the spec); with a `depthBinding` (one level:
   any binding but a stack) its value, clamped to −1..1, replaces `depth` each frame;
3. `add`: `value += depth · range · norm`; `multiply`: `value *= 1 − depth · (1 − norm)`;

and the result is clamped to the parameter (rounded for integers). Bass + LFO + keyframes on a `brightness`
parameter (0..1):

```dart
const brightness = StackedBinding(
  base: KeyframeBinding(keys: [Keyframe(at: 0, value: 0.2), Keyframe(at: 8, value: 0.6, easing: Easing.easeInOut)]),
  modulators: [
    // + up to 0.4 with the bass (its follower's 0..1 is the norm)
    Modulator(source: AudioBinding(feature: AudioFeatureKey.bass, min: 0, max: 1), depth: 0.4),
    // × a slow sine on the beat, dipping by at most 30 %
    Modulator(source: BeatBinding(shape: BeatShape.sine, periodBeats: 4, min: 0, max: 1), depth: 0.3,
        mode: ModulatorMode.multiply),
    // + a per-bar random accent whose depth is the "accent" macro
    Modulator(source: RandomBinding(mode: RandomMode.perBar, min: 0, max: 1), depth: 0.2,
        depthBinding: MacroBinding('accent')),
  ],
);
```

At 0.2 base, bass 0.5 and the sine at its top: `0.2 + 0.4 · 1 · 0.5 = 0.4`, `× (1 − 0.3 · 0) = 0.4`, plus the
accent. Only number and integer parameters accept stacks; a color parameter takes constants, color keyframes and
macros.

### Macros

A composition can define **macros**: named global bindings (`Intensity`, `Color A`, `Speed`…) that any clip
parameter reads through a `MacroBinding(macroId)`. The host passes them per bake as `BakeRequest.macros`
(`{macroId: ParamBinding}`); the resolver evaluates each macro every frame on the same clock as the parameters
(so a macro can be keyframed, audio-driven, random…; a stacked macro uses the unit range 0..1 as its depth unit),
then the parameters. One level only: a macro reading a macro resolves to nothing. A `MacroBinding` whose macro
the request does not define, or whose value does not fit the parameter (a color on a number, a macro reading a
macro), gives the parameter's **default**; as a modulator source a missing macro contributes nothing. The
macro's value is clamped to the parameter like any modulated value. `needsAudioFeatures` / `needsAudioClock`
(and the effect twins) take `macros:` and follow the `MacroBinding`s into them, as do
`BakeRequest.bindingsUseAudioFeatures` / `bindingsUseAudioClock`.

### Evaluation

`ParamResolver` evaluates the bindings frame by frame (`at(frameIndex)`), stepping the stateful ones — audio
followers, random glides, envelopes and trigger edges — once per frame, so call it in order; asking for an earlier
frame (or `reset()`) replays from frame 0, so the result never depends on the call pattern. It takes the request's
`macros` and `seed` (the setup's seed in a bake, the fallback seed of random bindings). Beat-based bindings
without a tempo count 120 BPM (`fallbackBpm`) on clip time.

### Audio features

`AudioFeatureExtractor.extract(monoPcm, sampleRate)` (or `add` chunks + `finish`) analyses a whole song into
`AudioFeatures`: one row per 10 ms with level, bass/mid/treble, spectral-flux onset, peak frequency and 16 mel
bands (40 Hz–16 kHz), each normalized to 0..1 per song. `sampleAt(t, tempo:)` gives an `AudioFrame`;
`contentHash` keys caches.

### Frequency ranges

Like LedFx's per-effect "frequency range", every audio-driven built-in generator lets the user choose which part
of the spectrum drives it, through one shared control (`lib/src/util/audio_range.dart`):

- `AudioRangePreset`: `full` (20 Hz–16 kHz), `lows` (20–250 Hz), `lowMids` (250–500 Hz), `mids` (500 Hz–2 kHz),
  `highMids` (2–4 kHz), `highs` (4–16 kHz) and `custom`, each with en + pl labels.
- `audioRangeParams({prefix: 'range', defaultPreset: lows})` — three specs to spread into a generator's `params`:
  the `ChoiceParam` `range` over the presets, and the `NumberParam`s `rangeLowHz` / `rangeHighHz` (20–16000 Hz,
  log scale, read only with the `custom` preset; reversed bounds are swapped).
- `audioRangeValue(params, audio)` → the energy (`0..1`) of the selected range: `AudioFrame.energyBetween`, the
  mean of the mel bands whose centers fall inside it (a range narrower than a band interpolates the spectrum at
  its geometric middle). `audioRangeOf(params)` gives the resolved `AudioRange` (`lowHz`, `highHz`, `energy`,
  and `frequencyAt(t)` / `spectrumAt(audio, t)` on the mel scale — how the spectrum generators zoom).
- `audioSourceParam()` (`source`: loudness / frequency range / hits / beat pulse) with `audioSourceValue` for a
  generator where either the level or a range makes sense.

Among the built-ins: `vu_meter` and `waveform_scroll` keep their `feature` choice, with the new `range` option
as the default; `bass_pulse` (default `lows`), `freq_color` (brightness), `onset_drops` (number and brightness
of the drops at a hit) and `ripple_peak` (ring size at a hit) follow the range; `spectrum` and `spectrum_mirror`
zoom into it (which part of the spectrum maps across the icicles, default `full`); `strobe`'s `trigger` gained
`range` ("Frequency range hit", default `lows`).

### Baking

```dart
final animation = bakeGenerator(const PlasmaGenerator(), BakeRequest.forLength(
  setup: const GeneratorSetup(xCount: 24, yCount: 20, radioPanelsCount: 2, radioPanelPixelCount: 10, seed: 1),
  length: const Duration(seconds: 30),
  bindings: {'brightness': const AudioBinding(feature: AudioFeatureKey.bass, min: 0.3, max: 1)},
  audio: features, // song-wide AudioFeatures, or null
  tempo: Tempo(bpm: 128), // on the same clock as the audio, or null
  audioOrigin: const Duration(seconds: 12), // song time of generator time 0
));
final index = animation.toIndex();
```

At most `maxBakeLength` (10 minutes); failures are `GeneratorException`s with a `GeneratorErrorKind`.
`frameIndexAt`/`frameCountFor` give the frame grid, `Tempo` the beat grid. `needsAudioFeatures` /
`needsAudioClock` tell whether a generator + bindings read the audio / depend on the song position.

## Built-in generators

`builtInGenerators` (const; look them up by id with `GeneratorRegistry`, `builtInGeneratorRegistry()`), each
with en + pl texts, 3–11 parameters (number parameters bindable) and a `panels` parameter where sensible.
Categories (`GeneratorCategory`): basic, motion, nature, particles, geometry, audio.

| Id | Category | What it does |
|---|---|---|
| `icicles.solid` | basic | one color everywhere |
| `icicles.gradient` | basic | a palette scrolling across/along the icicles |
| `icicles.rainbow` | basic | hues running over the icicles |
| `icicles.strobe` | basic | beat-synced flashes (120 BPM without a tempo) or flashes on hits of a frequency range / bass / onset |
| `icicles.breathe` | basic | the whole grid breathing (sine / exponential / linear, bindable rate) |
| `icicles.heartbeat` | basic | a double pulse at a heart rate, as a center glow or the whole grid |
| `icicles.wipe` | motion | a directional fill (6 directions, soft edge) that loops or holds — a transition layer |
| `icicles.chase` | motion | theater chase: segments running along or across the icicles |
| `icicles.scanner` | motion | a Cylon bar sweeping back and forth with a trail |
| `icicles.meteor` | motion | comets with tails falling down (or rising up) the icicles |
| `icicles.bounce` | motion | a ball per icicle dropping and bouncing off the tip (gravity, bounciness) |
| `icicles.marquee` | motion | alternating two-color bands scrolling in a direction |
| `icicles.bars` | motion | wide palette bars moving over the grid, with 3D shading |
| `icicles.snake` | motion | snakes crawling down one icicle and up the next (firmware Snake) |
| `icicles.slide` | motion | two-color blocks sliding one icicle at a time with elastic/bounce easing (firmware Slide) |
| `icicles.plasma` | nature | overlapping sine fields |
| `icicles.noise` | nature | simplex noise through a palette |
| `icicles.aurora` | nature | northern-light curtains |
| `icicles.waves` | nature | sine waves |
| `icicles.snow` | nature | falling snow |
| `icicles.water_drops` | nature | water drops |
| `icicles.candle` | nature | candle flicker per icicle / LED / whole grid |
| `icicles.lightning` | nature | random bursts of flashes over a few icicles with afterglow |
| `icicles.fire` | nature | Fire2012 per icicle, rising from the tips or pouring from the roof (heat or ice palette) |
| `icicles.icicle_drip` | nature | drops run down, swell at the tip and drip off; optional tip glow |
| `icicles.icicle_grow` | nature | icicles freeze from the roof to the tip and thaw back, each at its own pace |
| `icicles.rain` | nature | drops streaking down with a splash at the tip |
| `icicles.heatmap` | nature | wandering heat sources diffusing and cooling over the grid (firmware Heatmap) |
| `icicles.sparks` | particles | random sparks fading out |
| `icicles.fireflies` | particles | drifting pulsing glows |
| `icicles.twinkle` | particles | random LEDs fading in and out over a background color |
| `icicles.glitter` | particles | short white sparkles over a drifting palette |
| `icicles.fireworks` | particles | rockets rising from the tips and bursting into falling sparks |
| `icicles.ripple` | geometry | rings expanding from random (or center) points |
| `icicles.shockwave` | geometry | one ring from a chosen point on a timer or a bindable `trigger` (bind it to onset) |
| `icicles.radial` | geometry | pinwheel / spiral arms turning about the center |
| `icicles.shapes` | geometry | a pulsing circle, square, diamond or heart, outlined or filled (bindable size) |
| `icicles.curtain` | geometry | a curtain opening from the center or the edges, with a swag |
| `icicles.kaleidoscope` | geometry | noise mirrored into symmetric wedges |
| `icicles.lissajous` | geometry | a dot tracing a Lissajous figure with a trail |
| `icicles.life` | geometry | Conway's Game of Life, cells colored by age, reseeding when it settles |
| `icicles.text` | geometry | scrolling text (`TextParam`) in the 3×5 font; up/down turns the letters to read along the icicles |
| `icicles.vignette` | geometry | a brightness mask (spotlight, band, edge fade; bindable position) for the Multiply blend |
| `icicles.vu_meter` | audio | icicles fill with a frequency range (or the loudness), peak hold |
| `icicles.spectrum` | audio | the mel spectrum over the icicles, zoomed to a frequency range |
| `icicles.bass_pulse` | audio | a pulse from a frequency range (lows by default), kicking on the beat |
| `icicles.onset_drops` | audio | hits send drops down the icicles, as many and as bright as a frequency range |
| `icicles.spectrum_mirror` | audio | bands of a frequency range growing from the center, mirrored both ways, with peak dots |
| `icicles.waveform_scroll` | audio | the history of a frequency range (or the loudness) scrolling down as a waveform or glowing rows |
| `icicles.beat_bars` | audio | one bar per beat of the bar, flashing on its beat (120 BPM without a tempo) |
| `icicles.freq_color` | audio | hue from the loudest frequency, brightness from a frequency range |
| `icicles.ripple_peak` | audio | a ring per hit, colored by the pitch, sized by a frequency range |

## Effects

An **effect** is the counterpart of a generator for adjustment layers: instead of drawing from nothing, it takes
the layers composited below it (an `AnimationView`) and returns a modified view. It shares the parameter schema
and bindings, so the host builds the same UI and stores the same `{id: ParamBinding}` map, and the compositor
applies an *effect clip* per frame over everything beneath it on the track.

```dart
final class DimEffect implements Effect {
  const DimEffect();

  @override
  EffectInfo get info => const EffectInfo(
        id: 'my.plugin/dim', // built-ins use `icicles.fx.<name>`
        version: 1,
        name: LocalizedText('Dim', pl: 'Przyciemnienie'),
        description: LocalizedText('Darkens the layers below.', pl: 'Przyciemnia warstwy poniżej.'),
        category: EffectCategory.color, // color | transform | blur | dynamics | stylize
      );

  @override
  List<ParamSpec> get params => const [
        NumberParam(id: 'level', label: LocalizedText('Level', pl: 'Poziom'), min: 0, max: 1, defaultValue: 0.5),
        effectPanelsParam, // the standard `panels` switch: process the radio panels too
      ];

  @override
  EffectInstance create(GeneratorSetup setup) => const _Dim();
}

final class _Dim implements EffectInstance {
  const _Dim();

  @override
  void apply(FrameContext ctx, AnimationView input, Icicles out) {
    // `out` already holds `input`; only touch what changes.
    final level = ctx.params.number('level');
    for (var i = 0; i < input.frame.pixels.length; i++) {
      out.setPixelColorAtIndex(i, dim(input.frame.pixels[i], level));
    }
  }
}
```

`EffectInstance.apply(ctx, input, out)` gets the same `FrameContext` as a generator (time, resolved parameters,
audio, the seeded random) plus the read-only `input`; `out` is pre-filled with the input before every call.
Instances are created per run and see the frames in order, so stateful effects (trail, echo) keep their own
buffers. `EffectInfo.usesAudio` works like the generator's.

### Running an effect

```dart
final runner = EffectRunner(const TrailEffect(), BakeRequest.forLength(
  setup: setup, length: clipLength, bindings: bindings, audio: features, tempo: tempo, audioOrigin: origin,
));
// Per frame of the composite, in order:
final view = runner.applyAt(frameIndex, layersBelow); // keeps the input frame's duration
```

`EffectRunner` is sequential like `ParamResolver`: call `applyAt` with increasing frame indices; an earlier (or
the same) index starts the run over (fresh instance and random, bindings replayed), so the result depends only
on the inputs since the last restart. `reset()` does that explicitly. Failures are `GeneratorException`s:
`invalidRequest` for a bad request or an input of another layout, `renderFailed` when the effect throws.
`effectNeedsAudioFeatures` / `effectNeedsAudioClock` mirror the generator helpers. `FrameCodec` is the shared
RGB frame layout (`encodeView` / `decodeView` / `viewOf` / `checkView`).

### Built-in effects

`builtInEffects` (const; `EffectRegistry`, `builtInEffectRegistry()`), ids `icicles.fx.<name>`, each with en + pl
texts, 2–8 parameters (number parameters bindable) and a `panels` switch where sensible. Categories
(`EffectCategory`): color, transform, blur, dynamics, stylize.

| Id | Category | What it does |
|---|---|---|
| `icicles.fx.brightness` | color | gain, gamma and contrast (all 1 = unchanged) |
| `icicles.fx.hue_shift` | color | rotates the hues by `shift` turns (bindable → a hue cycle per beat) plus a continuous `rate` |
| `icicles.fx.saturation` | color | −1 washes out to grey, +1 boosts |
| `icicles.fx.invert` | color | inverts the channels, blended by `amount` |
| `icicles.fx.posterize` | color | snaps every channel to `levels` |
| `icicles.fx.threshold` | color | brighter than `cutoff` → `above` color (or its own), else `below` |
| `icicles.fx.palette_remap` | color | brightness through a `PaletteParam` (+ `offset`, keep black) |
| `icicles.fx.tint` | color | multiplies by a color, blended by `amount` |
| `icicles.fx.flip` | transform | left ↔ right, roof ↔ tips or both (panel order too) |
| `icicles.fx.mirror` | transform | one half onto the other (4 ways), quad, or a kaleidoscope of `segments` |
| `icicles.fx.offset` | transform | shifts by `dx`/`dy` pixels (bindable) and scrolls at `speedX`/`speedY` px/s, wrapping or not |
| `icicles.fx.rotate180` | transform | upside down (panel order and pixels too) |
| `icicles.fx.tile` | transform | `repeatX` × `repeatY` shrunken copies, optionally mirrored |
| `icicles.fx.zoom` | transform | scales about a center, nearest sampling, optional wrap (bindable scale → pump) |
| `icicles.fx.blur_vertical` | blur | a box blur along each icicle (`radius`, `mix`) |
| `icicles.fx.blur_box` | blur | a 2-D box blur (`radiusX`, `radiusY`, `mix`) |
| `icicles.fx.glow` | blur | pixels above `threshold` bloom: blur + add |
| `icicles.fx.trail` | dynamics | motion blur: pixels fade out with time constant `fade` (brightest-wins or add) |
| `icicles.fx.echo` | dynamics | `taps` delayed copies every `delay`, each `decay` dimmer |
| `icicles.fx.strobe_gate` | dynamics | shows the input for `duty` of every `rate` beats (120 BPM without a tempo) |
| `icicles.fx.flicker` | dynamics | the whole picture at a random brightness, `rate` changes per second |
| `icicles.fx.gate_audio` | dynamics | brightness follows a frequency range (`audioRangeParams`, floor, sensitivity, smoothing) |
| `icicles.fx.pixelate` | stylize | `blockX` × `blockY` blocks, average or brightest |
| `icicles.fx.shimmer` | stylize | random per-pixel brightness jitter (`amount`, `density`, `rate`) |
| `icicles.fx.fade_edges` | stylize | vignette multiply: all edges, sides, ends or a spotlight |
| `icicles.fx.noise_displace` | stylize | pixels pushed around by drifting simplex noise |

## Plugins

A plugin is a Dart program whose `main` serves generators over stdin/stdout:

```dart
import 'package:icicles_generators/plugin.dart';

Future<void> main() => runGeneratorPlugin(const [PulseGenerator()], pluginId: 'my.plugin', effects: const [DimEffect()]);
```

Compile it to a native executable on each target OS (`dart compile exe` does not cross-compile) and copy it into the
visualizer's plugins folder, then press "Refresh" on the editor's Generators tab (the folder button there opens it):

```sh
# macOS
dart compile exe bin/my_plugin.dart -o build/my_plugin
mkdir -p ~/Library/Application\ Support/it.klyta.iciclesVisualizer/plugins
cp build/my_plugin ~/Library/Application\ Support/it.klyta.iciclesVisualizer/plugins/   # must keep its x bit

# Windows (PowerShell)
dart compile exe bin\my_plugin.dart -o build\my_plugin.exe
Copy-Item build\my_plugin.exe "$env:APPDATA\it.klyta.iciclesVisualizer\plugins\"       # must be a .exe
```

The app starts every executable in that folder as a long-lived process (`hello` within 5 s, a bake within 60 s; a
crashed plugin is restarted once, then shown as unavailable until the next refresh) and logs its stderr. See
[`example/fire_plugin`](example/fire_plugin/README.md) for a complete plugin, Gatekeeper notes and a way to run it
without the app. `print` goes to stderr; never write to stdout.

The protocol: length-prefixed messages (`u32` header length, `u32` payload length, JSON header, binary payload).
The host sends `hello {protocol: 1}` and gets a `manifest` (generator and effect infos and parameter schemas;
`effects` is missing from plugins built before 0.4.0); a
`bake {requestId, generatorId, setup, frameCount, bindings, macros, tempo, audioOriginUs, audioHash}` (with the
audio features as payload once per hash) is answered by `frames` (per frame `u16` duration in ms + RGB bytes) and
`done`, or `error {kind, message}`. Effects: `audio {audioHash}` (+ the features as payload, cached by hash, no
reply) hands the plugin a song once, then `apply {requestId, effectId, version, setup, frameCount, bindings,
macros, tempo, audioOriginUs, audioHash}` carries the input frames as payload in the `frames` layout and is
answered like a bake. `bindings` and `macros` are `ParamBindingJson` maps; a plugin built with an older package
ignores `macros` and the binding kinds it does not know (they decode to nothing, so those parameters take their
defaults) — the host sends everything, the plugin's package decides what it understands. On the host, `GeneratorPluginClient` does the handshake, rebuilds a baked animation with
`FrameAssembler` (byte-identical to `bakeGenerator` in process) and returns the views of `applyEffect(effectId,
request, inputs)` (identical to an in-process `EffectRunner`).

## Tests

`dart test` (the end-to-end plugin test runs `example/fire_plugin` with `dart run`).
