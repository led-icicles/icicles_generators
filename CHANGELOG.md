## 0.7.0

- Universal audio reactivity (`lib/src/reactive/`): `AudioReactivity` (Equatable; `none` default, `defaults` =
  brightness on the lows at sensitivity 1, 10/150 ms) with `enabled`, `range: AudioRangePreset` + custom
  `lowHz`/`highHz`, `sensitivity` (0–4), `attack`/`release`, `threshold`, `invert` and `modes:
  Map<ReactiveModeKind, ReactiveMode>` — `brightness`, `speed`, `hue` (`hueSource` energy / frequency), `flash`
  (`trigger` beat / onset / range, `decay`, `flashColor`), `restart` (`trigger`), `size`; `ReactiveMode { min,
  max, … }`, `normalized`, `copyWith`, `withMode`, `isActive`, `usesAudioFeatures`, `usesTempo`, `audioRange`;
  `ReactiveModeKind.defaultMode` / `withDepth(depth)` / `depthOf(mode)` for a one-slider UI. JSON via
  `AudioReactivityJson.toJson` / `fromJson` (lenient; `modeToJson` / `modeFromJson`).
- `BakeRequest.reactivity` (and `forLength(reactivity:)`, part of equality; `usesAudioFeatures` /
  `usesAudioClock` / `withoutReactivity()`). `needsAudioFeatures`, `needsAudioClock`, `effectNeedsAudioFeatures`
  and `effectNeedsAudioClock` take `reactivity:`. An active reactivity wraps the program in a
  `ReactiveGeneratorInstance` / `ReactiveEffectInstance` inside `renderGeneratorFrames` / `bakeGenerator` /
  `EffectRunner`: the `ReactiveEngine` turns each frame's audio into a `ReactiveFrame` (energy follower,
  trigger edges, flash decay, time warp, restart count); native targets are written into the parameters
  (`reactiveParams`), the speed warps the frame clock otherwise (`time`/`delta`), a restart re-creates the
  instance with `ReactiveEngine.randomFor(seed, n)`, and `applyReactivePost` / `reactiveColor` dim, rotate and
  flash the rendered frame (the generator keeps its own frame buffer, so its previous-frame contract holds).
- `GeneratorInfo.reactiveTargets` / `EffectInfo.reactiveTargets: Map<ReactiveTarget, String>` (parameter id per
  `ReactiveTarget.brightness | speed | size | hue`; in the manifest as `reactiveTargets`); empty means by
  convention — `resolveReactiveTargets(declared, params)` takes the number parameters `brightness`, `speed`,
  `size`, `hue`.
- Plugin protocol: `bake` / `apply` headers carry an optional `reactivity` (`AudioReactivityJson`); the manifest
  carries `capabilities: ["reactivity"]` (`PluginProtocol.capabilityReactivity`, `PluginManifest.capabilities`
  / `supportsReactivity`). For a plugin without the capability the client sends the request without reactivity
  and post-processes the returned frames itself (`ReactivePostProcessor`: brightness / hue / flash; speed,
  restart and size need the plugin).

## 0.6.0

- `BeatGrid` (`lib/src/time/beat_grid.dart`): the real beats of a piece of music as instants — `beats`,
  `downbeats` (a subset), `bpm`, `confidence`, `source` (`'beat-this'` / `'autocorrelation'` / any label);
  `BeatGrid.regular(tempo, length:)` builds one from a `Tempo`. Clock math: `beatPositionAt`, `beatIndexAt`,
  `phaseAt`, `barPositionAt`, `barPhaseAt` (bars between downbeats, 4 beats from the first beat without any;
  outside the first/last beat the mean `beatPeriod` extrapolates), `nearestBeat`, `beatsBetween`,
  `downbeatsBetween`, `isDownbeat`, `shifted(offset)`, `toTempo()` (`bpm` from the first beat, clamped to the
  tempo range), `meanBpm` (the beat list's own mean tempo). Equatable; `BeatGridJson.toJson` / `fromJson` (`{beatsUs, downbeatsUs, bpm,
  confidence, source}`, malformed → `null`).
- The beat clock of a bake may be a `BeatGrid`: `BakeRequest.beats` (and `forLength(beats:)`, part of equality),
  `AudioFeatures.sampleAt(t, tempo:, beats:)`, `AudioFrame.fromColumns(…, beats:)`, `ParamResolver(beats:)`. When
  `beats` is given it wins over `tempo` for `beatPhase`/`barPhase`/`beatIndex`/`beatPulse`/`bpm`, the
  `BeatBinding` LFO, the beat/bar modes of `RandomBinding`, `StepBinding` (bars between the downbeats),
  `EnvelopeTrigger.beat`/`.bar` and `KeyTime.beats` (the grid's `bpm`); `Tempo` stays the fallback, and
  without either the behaviour is unchanged (`fallbackBpm` on clip time, `min` for the LFO).
- Plugin protocol: `bake` and `apply` headers carry an optional `beats` (`BeatGridJson`;
  `PluginProtocol.beatsToJson` / `beatsFromJson`). Older plugins ignore the key and follow `tempo`.

## 0.5.0

- Parameter animation (Phase G7, package A). New `ParamBinding` kinds, all with `ParamBindingJson` shapes,
  salvage/clamping in the specs and sequential, deterministic evaluation in `ParamResolver`:
  - `KeyframeBinding(keys, timeBase: KeyTime.seconds|beats, loop)` with `Keyframe(at, value, easing)` — number
    keys for number/integer parameters, `Color` keys for color parameters (HSV, shorter hue path; black keeps
    the other color's hue and saturation), Premiere-style segments eased by the first key's `Easing`
    (`hold | linear | easeIn | easeOut | easeInOut`, the cubic library curves, or `Easing.bezier(x1, y1, x2,
    y2)`), hold before/after, loop over the key span, beats = clip seconds × bpm / 60 (120 BPM without a tempo).
  - `RandomBinding(mode: perBeat|perBar|perTime|perFrame, interval, min, max, smooth, seed)` — sample-and-hold
    from `uniformHash(seed, holdIndex)` (seed defaults to the setup's), one-pole glide with `smooth`.
  - `StepBinding(steps, stepsPerBar, min, max, smooth, gate)` — a step sequencer in bar time (2…64 levels).
  - `EnvelopeBinding(trigger, attack, decay, sustain, release, sustainLevel, min, max, retrigger)` with
    `EnvelopeTrigger.beat | .bar | .onset(threshold) | .rangeHit(lowHz, highHz, threshold)` — AHDSR fired on
    rising edges; retrigger restarts the attack from the current level.
  - `StackedBinding(base, modulators)` + `Modulator(source, depth, mode: add|multiply, depthBinding)` —
    modulator stacking with sources normalized across their own range (parameter range for constants,
    keyframes and macros), one level of depth modulation; README documents the math.
  - `MacroBinding(macroId)` reads `BakeRequest.macros` (`{id: ParamBinding}`, evaluated per frame before the
    parameters, one level); an unknown macro gives the parameter's default. `BakeRequest` equality includes the
    macros; `needsAudioFeatures` / `needsAudioClock` / `effectNeeds…` take `macros:` and follow them;
    `bindingsUseAudio` / `bindingsUseTempo`, `BakeRequest.bindingsUseAudioFeatures` / `bindingsUseAudioClock`.
- `ParamResolver(macros:, seed:)` and `reset()`; `fallbackBpm` (120) for beat-based bindings without a tempo;
  `lerpHsv`. The baker and `EffectRunner` pass the setup seed and the request's macros.
- Plugin protocol: `bake` and `apply` carry `macros` (older plugins ignore the key and the binding kinds they
  do not know, so those parameters take their defaults). Manifest and parameter schemas are unchanged.
- Old projects decode unchanged: the existing JSON shapes, ids and salvage results are the same.

## 0.4.0

- Effects catalog, parallel to the generators: an `Effect` takes the layers composited below it (an
  `AnimationView`) and returns a modified view, with the same `ParamSpec`/binding schema, so the app can place
  effect clips (adjustment layers) on a track. Contract in `lib/src/effect/`: `EffectInfo` (the fields of
  `GeneratorInfo`, `category: EffectCategory { color, transform, blur, dynamics, stylize }`), `Effect`
  (`info`, `params`, `create(setup)`), `EffectInstance.apply(ctx, input, out)` (`out` pre-filled with the
  input), `EffectRegistry`, `builtInEffects`, `builtInEffectRegistry()`, `effectNeedsAudioFeatures` /
  `effectNeedsAudioClock`.
- `EffectRunner(effect, BakeRequest)` applies an effect frame by frame (`applyAt(frameIndex, input)`),
  sequential like `ParamResolver` (an earlier frame starts the run over), deterministic, failures as
  `GeneratorException`s (`invalidRequest` for an input of another layout, `renderFailed` when the effect
  throws).
- 26 built-in effects (ids `icicles.fx.<name>`, en + pl, 2–8 parameters, `panels` switch where sensible):
  brightness, hue_shift, saturation, invert, posterize, threshold, palette_remap, tint; flip, mirror, offset,
  rotate180, tile, zoom; blur_vertical, blur_box, glow; trail, echo, strobe_gate, flicker, gate_audio;
  pixelate, shimmer, fade_edges, noise_displace.
- `FrameCodec` (the RGB frame layout: `encodeIcicles`, `encodeView`, `decodeView`, `viewOf`, `checkView`) and
  `frameContextAt` (the `FrameContext` factory shared by the baker and the runner); color helpers `hsvOf`,
  `luma`, `colorFromUnit`.
- Plugin protocol: the manifest lists `effects: [{info, params}]` (plugins built before omit it); new host →
  plugin messages `audio {audioHash}` (+ features payload, cached by hash) and `apply {requestId, effectId,
  version, setup, frameCount, bindings, tempo, audioOriginUs, audioHash}` (+ the input frames as payload in the
  `frames` layout), answered with `frames` + `done` or `error`. `GeneratorPluginClient.applyEffect(effectId,
  request, inputs)` → `List<AnimationView>`, `PluginManifest.effects` / `findEffect`, `EffectManifestEntry`;
  `runGeneratorPlugin(generators, pluginId:, effects:)` and `serveGeneratorPlugin(…, effects:)` keep the old
  calls working.

## 0.3.0

- Frequency ranges, like LedFx's per-effect "frequency range": `AudioRangePreset` (full, lows, low mids, mids,
  high mids, highs, custom), `audioRangeParams()` (the `range` choice + the custom-only `rangeLowHz` /
  `rangeHighHz` log-scale numbers), `audioRangeOf` / `audioRangeValue`, `AudioRange` (`energy`, `frequencyAt`,
  `spectrumAt`) and `audioSourceParam()` / `audioSourceValue` (level / range / onset / beat pulse).
- `AudioFrame.energyBetween(lowHz, highHz)` (the mean of the mel bands whose centers fall in the range) and
  `AudioFrame.bandAtHz(hz)`.
- The audio-driven built-ins take the range params: `vu_meter` and `waveform_scroll` (`feature` gained the
  default option `range`; the Hz pair defaults to the full spectrum), `bass_pulse` (default lows — "a pulse from
  a frequency range"), `onset_drops` (drop count and brightness), `freq_color` (brightness), `ripple_peak` (ring
  size), `spectrum` / `spectrum_mirror` (zoom into the range, default full) and `strobe` (`trigger` option
  `range`, "Frequency range hit", default lows). Built-ins may now have up to 11 parameters.

## 0.2.0

- `TextParam` (free text of at most `maxLength` characters, `ParamValues.text`, stored as
  `{"type": "constant", "value": "…"}` like a choice and told apart by the spec at salvage; `kind: "text"` in the
  plugin manifest).
- `Direction` enum and the `directionParam(...)` choice preset (`up`/`down`/`left`/`right`/`in`/`out`) with
  `directionOf`; `Font3x5`, a 3×5 bitmap font (ASCII 32–90, `_`, `♥`, lowercase and Polish letters mapped).
- New `GeneratorCategory` values `motion` and `geometry`.
- 36 new built-in generators (52 in all): wipe, chase, scanner, breathe, meteor, bounce, marquee, bars, snake,
  slide, twinkle, glitter, candle, lightning, fire, icicle_drip, icicle_grow, rain, fireworks, heartbeat,
  ripple, shockwave, radial, shapes, curtain, kaleidoscope, lissajous, life, text, heatmap, vignette,
  spectrum_mirror, waveform_scroll, beat_bars, freq_color, ripple_peak.
- The example plugin's class is now `ExampleFireGenerator` (the built-in `FireGenerator` took the name).

## 0.1.0

- Initial version: generator contract, parameter schema and bindings, audio features and extractor, baking,
  built-in generators and the plugin protocol.
