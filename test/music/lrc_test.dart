import 'package:flutter_test/flutter_test.dart';
import 'package:yesplaymusic/music/lrc.dart';
import 'package:yesplaymusic/music/models.dart';

void main() {
  // 一行多个时间戳会展开成多行，并按时间排序；.5 是 500ms 而不是 5ms。
  test('repeated stamps expand and sort, fractions scale', () {
    final ls = parseLrc(
      '[ti:Song]\n[00:10.5][00:01.05]chorus\n[00:05.123]verse',
    );
    expect(ls.map((l) => (l.start, l.text)), [
      (1050, 'chorus'),
      (5123, 'verse'),
      (10500, 'chorus'),
    ]);
  });

  // 正 offset 让歌词提前，但不会早于 0。
  test('offset shifts lines earlier and clamps at zero', () {
    final ls = parseLrc('[offset:+500]\n[00:00.20]a\n[00:02.00]b');
    expect(ls.map((l) => l.start), [0, 1500]);
  });

  test('trailing offset shifts all line and word timestamps', () {
    final ls = parseLrc(
      '[00:00.20]Intro\n'
      '[00:02.00]<00:02.00>Moon <00:02.50>river<00:03.00>\n'
      '[offset:+500]',
    );
    expect(
      [ls.map((l) => l.start), ls.last.words.map((w) => (w.start, w.end))],
      [
        [0, 1500],
        [(1500, 2000), (2000, 2500)],
      ],
    );
  });

  test('oversized offset is ignored and lines stay unshifted', () {
    final ls = parseLrc(
      '[offset:+500]\n[offset:99999999999999999999]\n[00:01.00]a\n[00:02.00]b',
    );
    expect(ls.map((l) => l.start), [1000, 2000]);
  });

  // 增强 LRC 的逐字时间：每个字到下一个时间标记结束，文本是字拼起来。
  test('word timing from enhanced LRC', () {
    final l = parseLrc('[00:01.00]<00:01.00>Moon <00:01.50>river<00:02.00>')
        .single;
    expect(l.text, 'Moon river');
    expect(l.words.map((w) => (w.start, w.end, w.text)), [
      (1000, 1500, 'Moon '),
      (1500, 2000, 'river'),
    ]);
  });

  test('enhanced LRC keeps text before the first inline timestamp', () {
    final l = parseLrc('[00:02.000]Open <00:02.800>the <00:03.100>door').single;
    expect(l.text, 'Open the door');
    expect(l.words.map((w) => (w.start, w.end, w.text)), [
      (2000, 2800, 'Open '),
      (2800, 3100, 'the '),
      (3100, 0, 'door'),
    ]);
  });

  test(
    'enhanced LRC times the prefix from each offset-adjusted line stamp',
    () {
      final lines = parseLrc(
        '[00:01.00][00:02.00]Open <00:02.80>the door<00:04.00>\n'
        '[offset:+500]',
      );
      expect(
        lines.map((l) => (l.start, l.words.first.start, l.words.first.end)),
        [(500, 500, 2300), (1500, 1500, 2300)],
      );
    },
  );

  test('enhanced LRC prefix cannot end before a repeated line stamp', () {
    final lines = parseLrc('[00:01.00][00:10.00]Open <00:02.00>the door');
    expect(lines.map((l) => (l.words.first.start, l.words.first.end)), [
      (1000, 2000),
      (10000, 10000),
    ]);
  });

  test('malformed-only inline tags fall back to plain text', () {
    for (final tag in ['<00:xx>', '<999999999999999999999:01.00>']) {
      final l = parseLrc('[00:02.00]Open ${tag}the door').single;
      expect(l.text, 'Open ${tag}the door');
      expect(l.words, isEmpty);
    }
  });

  test('malformed inline tags stay literal next to valid inline timing', () {
    for (final tag in ['<00:xx>', '<999999999999999999999:01.00>']) {
      final l = parseLrc('[00:02.00]Open ${tag}the <00:03.10>door').single;
      expect(l.text, 'Open ${tag}the door');
      expect(l.words.map((w) => (w.start, w.end, w.text)), [
        (2000, 3100, 'Open ${tag}the '),
        (3100, 0, 'door'),
      ]);
    }
  });

  test('enhanced LRC keeps the prefix on same-stamp translations', () {
    final l = lyricLines(
      const Lyrics(lrc: '[00:02.00]Open the door\n[00:02.00]把<00:02.80>门打开'),
    ).single;
    expect(l.translation, '把门打开');
  });

  // 原文下一行用同一时间戳写翻译时，第二行并进上一行的 translation。
  test('same-stamp second line becomes translation', () {
    final ls = lyricLines(
      const Lyrics(
        lrc: '[00:01.00]Moon river\n[00:01.00]月亮河\n[00:04.00]Wider\n[00:04.00]更宽',
      ),
    );
    expect(ls.map((l) => (l.text, l.translation)), [
      ('Moon river', '月亮河'),
      ('Wider', '更宽'),
    ]);
    expect(ls.first.end, 4000);
  });

  // 单独的翻译 LRC 按时间对上原文，允许几十毫秒的误差。
  test('separate translation matches nearby stamps', () {
    final ls = lyricLines(
      const Lyrics(
        lrc: '[00:01.00]Moon river\n[00:04.00]Wider',
        translation: '[00:01.04]月亮河\n[00:09.00]不相干',
      ),
    );
    expect(ls.map((l) => l.translation), ['月亮河', '']);
  });

  test('separate translation picks the closest stamp within 100 ms', () {
    final ls = lyricLines(
      const Lyrics(
        lrc:
            '[00:01.10]Closest\n'
            '[00:02.10]Tie\n'
            '[00:03.10]Exact\n'
            '[00:04.10]At the limit\n'
            '[00:05.10]Outside the limit',
        translation:
            '[00:01.12]Closest translation\n'
            '[00:01.02]Earlier but farther translation\n'
            '[00:02.15]Later tied translation\n'
            '[00:02.05]Earlier tied translation\n'
            '[00:03.05]Nearby translation\n'
            '[00:03.10]Exact translation\n'
            '[00:04.00]Boundary translation\n'
            '[00:05.201]Too far',
      ),
    );
    expect(ls.map((l) => l.translation), [
      'Closest translation',
      'Earlier tied translation',
      'Exact translation',
      'Boundary translation',
      '',
    ]);
  });

  test('same-stamp translations also supply the closest nearby cue', () {
    final ls = lyricLines(
      const Lyrics(
        lrc:
            '[00:01.02]Earlier line\n[00:01.02]Earlier translation\n'
            '[00:01.10]Line without exact translation\n'
            '[00:01.12]Later line\n[00:01.12]Later translation',
      ),
    );
    expect(ls.map((l) => l.translation), [
      'Earlier translation',
      'Later translation',
      'Later translation',
    ]);
  });

  // 插件直接给逐行歌词时，原样使用，不再解析 lrc。
  test('timed lines win over lrc', () {
    final ls = lyricLines(
      const Lyrics(
        lrc: '[00:01.00]ignored',
        lines: [LyricLine(start: 7, text: 'kept')],
      ),
    );
    expect(ls.single.text, 'kept');
  });

  // 二分查找当前行：第一行之前是 -1，正好在时间点上算这一行。
  test('lineAt finds the current line', () {
    final ls = parseLrc('[00:01.00]a\n[00:02.00]b\n[00:03.00]c');
    expect([0, 1000, 1999, 2000, 99999].map((t) => lineAt(ls, t)), [
      -1,
      0,
      0,
      1,
      2,
    ]);
  });

  test('repeated stamps separated by spaces expand into clean lyrics', () {
    final ls = parseLrc('[00:02.00] [00:18.00]chorus');
    expect(ls.map((l) => (l.start, l.text)), [(2000, 'chorus'), (18000, 'chorus')]);
  });

  // 相同时间戳的原文/翻译行必须保持输入顺序（稳定排序）。
  test('mergeSort keeps input order for equal timestamps', () {
    final buf = StringBuffer();
    for (var i = 0; i < 24; i++) {
      final ss = (i + 1).toString().padLeft(2, '0');
      buf.writeln('[00:$ss.00]orig$i');
      buf.writeln('[00:$ss.00]trans$i');
    }
    final ls = parseLrc(buf.toString());
    expect(ls.length, 48);
    for (var i = 0; i < 24; i++) {
      final oi = ls.indexWhere((l) => l.text == 'orig$i');
      final ti = ls.indexWhere((l) => l.text == 'trans$i');
      expect(oi, isNonNegative);
      expect(ti, isNonNegative);
      expect(oi, lessThan(ti));
    }
    for (var i = 1; i < ls.length; i++) {
      expect(ls[i].start, greaterThanOrEqualTo(ls[i - 1].start));
    }
  });
}
