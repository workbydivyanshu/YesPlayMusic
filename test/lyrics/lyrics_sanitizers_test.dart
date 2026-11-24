import 'package:flutter_test/flutter_test.dart';
import 'package:yesplaymusic/lyrics/lyrics_models.dart';
import 'package:yesplaymusic/lyrics/lyrics_repository.dart';

void main() {
  group('cleanSongTitle', () {
    test('strips (Official Video)', () {
      expect(cleanSongTitle('Song (Official Video)'), 'Song');
    });
    test('strips [Remastered]', () {
      expect(cleanSongTitle('Song [Remastered]'), 'Song');
    });
    test('strips - Live suffix', () {
      expect(cleanSongTitle('Song - Live'), 'Song');
    });
    test('returns original when empty', () {
      expect(cleanSongTitle(''), '');
    });
  });

  group('cleanSongArtist', () {
    test('strips - Topic', () {
      expect(cleanSongArtist('Artist - Topic'), 'Artist');
    });
    test('strips feat. X', () {
      expect(cleanSongArtist('Artist feat. Someone'), 'Artist');
    });
  });

  group('normalizeLyricsTitle', () {
    test('lowercases and strips bracketed noise', () {
      expect(normalizeLyricsTitle('ALL CAPS [Official Audio]'), 'all caps');
    });
    test('strips feat clauses', () {
      expect(normalizeLyricsTitle('Song feat. Someone'), 'song');
    });
  });

  group('lyricsTitlesMatch', () {
    test('exact match true', () {
      expect(lyricsTitlesMatch('Song', 'Song'), isTrue);
    });
    test('"Song (Interlude)" vs "Song" false', () {
      expect(lyricsTitlesMatch('Song (Interlude)', 'Song'), isFalse);
    });
    test('substring homonym rejected', () {
      expect(lyricsTitlesMatch('All', 'All Caps'), isFalse);
    });
  });

  group('lyricsArtistsMatch', () {
    test('equal true', () {
      expect(lyricsArtistsMatch('Madvillain', 'Madvillain'), isTrue);
    });
    test('shorter name inside longer billing true', () {
      expect(lyricsArtistsMatch('Madvillain', 'Madvillain & MF DOOM'), isTrue);
    });
    test('unrelated false', () {
      expect(lyricsArtistsMatch('Madvillain', 'Beyonce'), isFalse);
    });
  });

  group('lyricsDurationPlausible', () {
    test('within 12s true', () {
      expect(lyricsDurationPlausible(200, 205), isTrue);
    });
    test('within 20% true', () {
      expect(lyricsDurationPlausible(200, 230), isTrue);
    });
    test('way off false', () {
      expect(lyricsDurationPlausible(200, 400), isFalse);
    });
    test('null query true', () {
      expect(lyricsDurationPlausible(null, 400), isTrue);
    });
  });

  group('lyricsLooksLikePlaceholder', () {
    test('all note glyphs true', () {
      final r = LyricsResult(lines: const [LyricLine(timeMs: 0, text: '♪')]);
      expect(lyricsLooksLikePlaceholder(r), isTrue);
    });
    test('[instrumental] true', () {
      final r = LyricsResult(
        lines: const [LyricLine(timeMs: 0, text: '[instrumental]')],
      );
      expect(lyricsLooksLikePlaceholder(r), isTrue);
    });
    test('plainLyrics note glyphs true', () {
      const r = LyricsResult(plainLyrics: '♪\n♫');
      expect(lyricsLooksLikePlaceholder(r), isTrue);
    });
    test('real text false', () {
      final r = LyricsResult(
        lines: const [LyricLine(timeMs: 0, text: 'Hello world')],
      );
      expect(lyricsLooksLikePlaceholder(r), isFalse);
    });
  });
}
