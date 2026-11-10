import 'package:icicles_animation_dart/icicles_animation_dart.dart';

/// Index of the grid frame displayed at [time]: the largest `i` with
/// `framerate.frameStart(i) <= time`.
///
/// The grid is the library's drift-free millisecond timeline
/// ([Framerate.frameStart] / [Framerate.frameDuration]); the preview and the
/// export both sample it, so they are frame-identical.
int frameIndexAt(Framerate framerate, Duration time) {
  if (time.isNegative) {
    throw RangeError.value(time.inMicroseconds, 'time', 'Must not be negative.');
  }
  var index = time.inMicroseconds * framerate.framesPerSecond ~/ Duration.microsecondsPerSecond;
  while (index > 0 && framerate.frameStart(index) > time) {
    index--;
  }
  while (framerate.frameStart(index + 1) <= time) {
    index++;
  }
  return index;
}

/// Number of grid frames needed to cover `[0, duration)`.
int frameCountFor(Framerate framerate, Duration duration) =>
    duration <= Duration.zero ? 0 : frameIndexAt(framerate, duration - const Duration(microseconds: 1)) + 1;
