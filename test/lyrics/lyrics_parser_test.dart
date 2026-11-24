import 'package:flutter_test/flutter_test.dart';
import 'package:yesplaymusic/lyrics/lyrics_models.dart';
import 'package:yesplaymusic/lyrics/lyrics_providers.dart';

void main() {
  group('parseLrc robustness', () {
    test('empty string -> empty', () {
      expect(parseLrc(''), isEmpty);
    });
    test('garbage without timestamp -> empty, no throw', () {
      expect(() => parseLrc('not a timestamp'), returnsNormally);
      expect(parseLrc('not a timestamp'), isEmpty);
    });
    test('single timed line -> one line with text', () {
      final lines = parseLrc('[00:01.00]Hello');
      expect(lines, hasLength(1));
      expect(lines.single.text, 'Hello');
    });
  });

  group('parseEnhancedLrc robustness', () {
    test('garbage -> no throw, empty', () {
      expect(() => parseEnhancedLrc('garbage'), returnsNormally);
      expect(parseEnhancedLrc('garbage'), isEmpty);
    });
  });

  group('parseTtml robustness', () {
    test('invalid fragment -> no throw, empty', () {
      expect(() => parseTtml('<not valid'), returnsNormally);
      expect(parseTtml('<not valid'), isEmpty);
    });
    test('minimal valid TTML -> lines', () {
      const ttml =
          '<tt><body><div><p begin="0s" end="2s">Hello</p>'
          '</div></body></tt>';
      final lines = parseTtml(ttml);
      expect(lines, isNotEmpty);
      expect(lines.first.text, contains('Hello'));
    });
  });

  group('parseKugouKrc robustness', () {
    test('garbage -> no throw, empty', () {
      expect(() => parseKugouKrc('garbage not krc'), returnsNormally);
      expect(parseKugouKrc('garbage not krc'), isEmpty);
    });
  });
}
