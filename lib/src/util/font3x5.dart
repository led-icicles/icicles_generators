/// A compact 3×5 bitmap font for the scrolling-text generator.
///
/// Glyphs cover ASCII 32–90 (space, punctuation, digits, capitals) plus a
/// heart (`♥`) and `_`; lowercase letters map to capitals and Polish letters
/// (ą, ć, ę, ł, ń, ó, ś, ź, ż) to their base letters. Unknown characters
/// render as a blank glyph. Each glyph is 5 rows of 3 bits, bit 2 being the
/// left column.
abstract final class Font3x5 {
  static const int width = 3;
  static const int height = 5;

  /// Columns between glyphs.
  static const int spacing = 1;

  static const _glyphs = <int, List<int>>{
    0x20: [0, 0, 0, 0, 0], // space
    0x21: [2, 2, 2, 0, 2], // !
    0x22: [5, 5, 0, 0, 0], // "
    0x23: [5, 7, 5, 7, 5], // #
    0x24: [3, 6, 2, 3, 6], // $
    0x25: [5, 1, 2, 4, 5], // %
    0x26: [2, 5, 2, 5, 3], // &
    0x27: [2, 2, 0, 0, 0], // '
    0x28: [1, 2, 2, 2, 1], // (
    0x29: [4, 2, 2, 2, 4], // )
    0x2A: [5, 2, 7, 2, 5], // *
    0x2B: [0, 2, 7, 2, 0], // +
    0x2C: [0, 0, 0, 2, 4], // ,
    0x2D: [0, 0, 7, 0, 0], // -
    0x2E: [0, 0, 0, 0, 2], // .
    0x2F: [1, 1, 2, 4, 4], // /
    0x30: [7, 5, 5, 5, 7], // 0
    0x31: [2, 6, 2, 2, 7], // 1
    0x32: [7, 1, 7, 4, 7], // 2
    0x33: [7, 1, 7, 1, 7], // 3
    0x34: [5, 5, 7, 1, 1], // 4
    0x35: [7, 4, 7, 1, 7], // 5
    0x36: [7, 4, 7, 5, 7], // 6
    0x37: [7, 1, 1, 1, 1], // 7
    0x38: [7, 5, 7, 5, 7], // 8
    0x39: [7, 5, 7, 1, 7], // 9
    0x3A: [0, 2, 0, 2, 0], // :
    0x3B: [0, 2, 0, 2, 4], // ;
    0x3C: [1, 2, 4, 2, 1], // <
    0x3D: [0, 7, 0, 7, 0], // =
    0x3E: [4, 2, 1, 2, 4], // >
    0x3F: [7, 1, 3, 0, 2], // ?
    0x40: [7, 5, 7, 4, 7], // @
    0x41: [7, 5, 7, 5, 5], // A
    0x42: [6, 5, 6, 5, 6], // B
    0x43: [7, 4, 4, 4, 7], // C
    0x44: [6, 5, 5, 5, 6], // D
    0x45: [7, 4, 7, 4, 7], // E
    0x46: [7, 4, 7, 4, 4], // F
    0x47: [7, 4, 5, 5, 7], // G
    0x48: [5, 5, 7, 5, 5], // H
    0x49: [7, 2, 2, 2, 7], // I
    0x4A: [1, 1, 1, 5, 7], // J
    0x4B: [5, 5, 6, 5, 5], // K
    0x4C: [4, 4, 4, 4, 7], // L
    0x4D: [5, 7, 7, 5, 5], // M
    0x4E: [6, 5, 5, 5, 5], // N
    0x4F: [7, 5, 5, 5, 7], // O
    0x50: [7, 5, 7, 4, 4], // P
    0x51: [7, 5, 5, 7, 1], // Q
    0x52: [7, 5, 6, 5, 5], // R
    0x53: [7, 4, 7, 1, 7], // S
    0x54: [7, 2, 2, 2, 2], // T
    0x55: [5, 5, 5, 5, 7], // U
    0x56: [5, 5, 5, 5, 2], // V
    0x57: [5, 5, 7, 7, 5], // W
    0x58: [5, 5, 2, 5, 5], // X
    0x59: [5, 5, 2, 2, 2], // Y
    0x5A: [7, 1, 2, 4, 7], // Z
    0x5F: [0, 0, 0, 0, 7], // _
    0x2665: [5, 7, 7, 2, 0], // ♥
  };

  static const _blank = [0, 0, 0, 0, 0];

  static const _polish = <int, int>{
    0x104: 0x41, 0x105: 0x41, // Ą ą
    0x106: 0x43, 0x107: 0x43, // Ć ć
    0x118: 0x45, 0x119: 0x45, // Ę ę
    0x141: 0x4C, 0x142: 0x4C, // Ł ł
    0x143: 0x4E, 0x144: 0x4E, // Ń ń
    0xD3: 0x4F, 0xF3: 0x4F, // Ó ó
    0x15A: 0x53, 0x15B: 0x53, // Ś ś
    0x179: 0x5A, 0x17A: 0x5A, // Ź ź
    0x17B: 0x5A, 0x17C: 0x5A, // Ż ż
  };

  /// The 5 row masks of the character with code point [rune] (blank for an
  /// unknown one).
  static List<int> glyph(int rune) {
    var code = _polish[rune] ?? rune;
    if (code >= 0x61 && code <= 0x7A) code -= 0x20;
    return _glyphs[code] ?? _blank;
  }

  /// The glyphs of [text], one per rune.
  static List<List<int>> glyphs(String text) => [for (final rune in text.runes) glyph(rune)];

  /// Columns [glyphs] take, including the spacing between them.
  static int textWidth(List<List<int>> glyphs) => glyphs.isEmpty ? 0 : glyphs.length * (width + spacing) - spacing;

  /// Whether the pixel at text column [column] and row [row] is set.
  static bool pixel(List<List<int>> glyphs, int column, int row) {
    if (column < 0 || row < 0 || row >= height) return false;
    final index = column ~/ (width + spacing);
    final within = column % (width + spacing);
    if (index >= glyphs.length || within >= width) return false;
    return (glyphs[index][row] >> (width - 1 - within)) & 1 == 1;
  }
}
