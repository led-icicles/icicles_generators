import 'package:equatable/equatable.dart';

/// A user-facing text in the languages the app ships (English and Polish).
///
/// Generators carry their names and labels as data; the widgets pick the
/// language with [of].
final class LocalizedText extends Equatable {
  /// English text, also the fallback for any other language.
  final String en;

  /// Polish text; `null` falls back to [en].
  final String? pl;

  const LocalizedText(this.en, {this.pl});

  /// The text for [languageCode] (`en`, `pl`, …), [en] when there is none.
  String of(String languageCode) => switch (languageCode) {
        'pl' => pl ?? en,
        _ => en,
      };

  @override
  List<Object?> get props => [en, pl];

  @override
  String toString() => en;
}
