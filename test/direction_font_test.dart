import 'package:icicles_generators/icicles_generators.dart';
import 'package:test/test.dart';

void main() {
  group('directionParam', () {
    test('is a choice over the direction ids with en + pl labels', () {
      final spec = directionParam();
      expect(spec.id, 'direction');
      expect(spec.options.map((o) => o.id), ['up', 'down', 'left', 'right', 'in', 'out']);
      expect(spec.defaultValue, 'down');
      for (final option in spec.options) {
        expect(option.label.pl, isNotNull);
      }
      expect(spec.salvage(const ConstantBinding('in')), const ConstantBinding('in'));
      expect(spec.salvage(const ConstantBinding('sideways')), const ConstantBinding('down'));
    });

    test('can be narrowed and renamed', () {
      final spec =
          directionParam(id: 'fall', options: const [Direction.up, Direction.down], defaultValue: Direction.up);
      expect(spec.id, 'fall');
      expect(spec.options.map((o) => o.id), ['up', 'down']);
      expect(spec.defaultValue, 'up');
      expect(() => directionParam(options: const [Direction.left], defaultValue: Direction.up), throwsArgumentError);
    });

    test('directionOf reads the value, Direction helpers', () {
      expect(directionOf(const ParamValues({'direction': 'out'})), Direction.outward);
      expect(directionOf(const ParamValues({'fall': 'up'}), 'fall'), Direction.up);
      expect(Direction.fromId('nope'), Direction.down);
      expect(Direction.inward.reversed, Direction.outward);
      expect(Direction.left.isHorizontal, isTrue);
      expect(Direction.up.isVertical, isTrue);
      expect(Direction.inward.isRadial, isTrue);
      expect(const ParamValues({'t': 'abc'}).text('t'), 'abc');
    });
  });

  group('Font3x5', () {
    test('has every glyph of ASCII 32–90 as 5 rows of 3 bits', () {
      for (var code = 32; code <= 90; code++) {
        final glyph = Font3x5.glyph(code);
        expect(glyph, hasLength(5), reason: 'U+${code.toRadixString(16)}');
        expect(glyph.every((row) => row >= 0 && row <= 7), isTrue);
        if (code != 32) expect(glyph.any((row) => row != 0), isTrue, reason: 'U+${code.toRadixString(16)} is blank');
      }
    });

    test('maps lowercase and Polish letters to capitals, unknown to blank', () {
      expect(Font3x5.glyph('a'.runes.first), Font3x5.glyph('A'.runes.first));
      expect(Font3x5.glyph('ł'.runes.first), Font3x5.glyph('L'.runes.first));
      expect(Font3x5.glyph('Ż'.runes.first), Font3x5.glyph('Z'.runes.first));
      expect(Font3x5.glyph('ó'.runes.first), Font3x5.glyph('O'.runes.first));
      expect(Font3x5.glyph('日'.runes.first), [0, 0, 0, 0, 0]);
      expect(Font3x5.glyph('♥'.runes.first).any((row) => row != 0), isTrue);
    });

    test('lays glyphs out with one blank column between them', () {
      final glyphs = Font3x5.glyphs('IT');
      expect(Font3x5.textWidth(glyphs), 7);
      expect(Font3x5.textWidth(const []), 0);
      // 'I' = 111/010/010/010/111: top row all set, middle column below.
      expect([for (var c = 0; c < 3; c++) Font3x5.pixel(glyphs, c, 0)], [true, true, true]);
      expect([for (var c = 0; c < 3; c++) Font3x5.pixel(glyphs, c, 2)], [false, true, false]);
      // The spacing column, then 'T' = 111/010/…
      expect(Font3x5.pixel(glyphs, 3, 0), isFalse);
      expect([for (var c = 4; c < 7; c++) Font3x5.pixel(glyphs, c, 0)], [true, true, true]);
      expect(Font3x5.pixel(glyphs, 5, 4), isTrue);
      expect(Font3x5.pixel(glyphs, 4, 4), isFalse);
      expect(Font3x5.pixel(glyphs, 7, 0), isFalse);
      expect(Font3x5.pixel(glyphs, -1, 0), isFalse);
      expect(Font3x5.pixel(glyphs, 0, 5), isFalse);
    });
  });
}
