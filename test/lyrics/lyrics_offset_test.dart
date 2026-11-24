import 'package:flutter_test/flutter_test.dart';
import 'package:yesplaymusic/lyrics/lyrics_models.dart';

List<LyricLine> _lines() => const [
  LyricLine(timeMs: 0, text: 'first'),
  LyricLine(timeMs: 5000, text: 'second'),
  LyricLine(timeMs: 10000, text: 'third'),
];

void main() {
  final lines = _lines();

  test('index at position 0 -> 0', () {
    expect(activeLyricLineIndex(lines, 0), 0);
  });

  test('index at 6000ms -> 1', () {
    expect(activeLyricLineIndex(lines, 6000), 1);
  });

  test('index at 11000ms -> 2', () {
    expect(activeLyricLineIndex(lines, 11000), 2);
  });

  test('extreme negative position -> before first cue, no throw', () {
    expect(() => activeLyricLineIndex(lines, -100000), returnsNormally);
    expect(activeLyricLineIndex(lines, -100000), -1);
  });

  test('extreme large position -> last index, no throw', () {
    final huge = 1 << 40;
    expect(() => activeLyricLineIndex(lines, huge), returnsNormally);
    expect(activeLyricLineIndex(lines, huge), lines.length - 1);
  });

  test('empty list -> -1', () {
    expect(activeLyricLineIndex(const [], 0), -1);
  });
}
