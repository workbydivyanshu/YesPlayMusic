// 正在播放页：右侧封面按窗口宽高自适应缩放、不侵入左侧歌词区，空间受限时在右侧区域内垂直居中。
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yesplaymusic/data.dart';
import 'package:yesplaymusic/music/eq.dart';
import 'package:yesplaymusic/music/models.dart' as m;
import 'package:yesplaymusic/music/player.dart';
import 'package:yesplaymusic/music/source.dart';
import 'package:yesplaymusic/pages/now_playing.dart';
import 'package:yesplaymusic/state.dart';
import 'package:yesplaymusic/ui.dart' show Cover;

import 'pages_smoke_test.dart' show appFor, prepareEnv;

/// Fake source: serves a fixed LRC (first cue at 5s) and a dummy stream.
class _LyricsSource extends Source {
  @override
  final m.SourceInfo info = const m.SourceInfo(id: 'fake', name: 'fake');
  @override
  final Set<String> ops = {Op.stream, Op.lyrics};
  @override
  Future<m.AudioStream> stream(String id, {String quality = 'high'}) async =>
      m.AudioStream(url: 'file:///song.flac', type: 'flac');
  @override
  Future<m.Lyrics> lyrics(String id) async =>
      const m.Lyrics(lrc: '[00:05.00]First line\n[00:10.00]Second line');
}

/// Fake engine: never touches mpv; reports position on demand.
class _FakeEngine implements PlaybackEngine {
  String? current;
  @override
  String? queuedKey;
  @override
  Duration duration = Duration.zero;
  @override
  void Function(Duration)? onPosition, onDuration;
  @override
  void Function(bool)? onPlaying;
  @override
  void Function()? onCompleted;
  @override
  void Function(String)? onError;
  @override
  void Function(String)? onAdvanced;

  void at(double pos) => onPosition!(Duration(milliseconds: (pos * 1000).round()));

  @override
  Future<Duration> readDuration() async => duration;
  @override
  Future<void> open(m.AudioStream s,
      {required String key,
      bool play = true,
      Duration? start,
      String rg = 'no',
      double gainDb = 0}) async {
    current = key;
    queuedKey = null;
  }

  @override
  Future<void> queueNext(m.AudioStream s,
      {required String key, String rg = 'no', double gainDb = 0}) async {}
  @override
  Future<void> dropQueued() async {}
  @override
  Future<void> setReplayGain(String rg, double gainDb) async {}
  @override
  Future<void> setEq(EqSettings s) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration d) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> setFade(double f) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late AppState app;

  setUpAll(prepareEnv);

  setUp(() {
    app = AppState();
    app.clearQueue();
    app.playList(const [
      Track(
        title: '测试歌曲',
        artist: '测试歌手',
        album: '测试专辑',
        cover: '',
        seconds: 200,
      ),
    ]);
  });
  tearDown(() => app.dispose());

  Future<Rect> measureCover(WidgetTester t, Size window) async {
    t.view.physicalSize = window;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appFor(app));
    app.openNowPlaying(NpTab.lyrics);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    final cover = find.descendant(
      of: find.byType(NowPlayingPage),
      matching: find.byType(Cover),
    );
    expect(cover, findsOneWidget);
    return t.getRect(cover);
  }

  testWidgets('右侧封面随窗口宽高自适应且不侵入左侧歌词区，受限时垂直居中', (t) async {
    final r1280 = await measureCover(t, const Size(1280, 800));
    final r1440 = await measureCover(t, const Size(1440, 900));
    final r1920 = await measureCover(t, const Size(1920, 1080));
    final rNarrowTall = await measureCover(t, const Size(1280, 1200));

    // 随窗口变大而放大，最小窗口下缩小以避开左侧歌词区（x = 820）
    expect(r1280.width, lessThan(r1440.width));
    expect(r1440.width, lessThan(r1920.width));
    expect(r1280.left, greaterThan(820));
    expect(r1440.left, greaterThan(820));
    expect(r1920.left, greaterThan(820));

    // 窄而高的窗口里受宽度限制无法放大，应在右侧区域 [80, H - 110] 内垂直居中
    expect(rNarrowTall.width, closeTo(r1280.width, 1.0));
    const expectedCenterY = 80.0 + (1200.0 - 80.0 - 110.0) / 2;
    expect(rNarrowTall.center.dy, closeTo(expectedCenterY, 2.0));
  });

  testWidgets('intro dims upcoming lyrics, wheel is safe, mini lyric hidden', (t) async {
    final engine = _FakeEngine();
    AppState.engineFactory = () => engine;
    addTearDown(() => AppState.engineFactory = AudioEngine.new);
    app.sources.add(_LyricsSource());
    app.clearQueue();
    app.playList([
      Track.of(
        const m.Track(id: 'song', name: '测试歌曲', source: 'fake', duration: 200000),
      ),
    ]);
    // Non-local sources defer opening ~300ms on a real timer.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await _frames(t);
    expect(app.lyricLines, isNotEmpty);
    expect(app.lyricIndex, -1); // position 0 is before the 5s first cue

    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appFor(app));
    app.openNowPlaying(NpTab.lyrics);
    await _frames(t);
    expect(t.takeException(), isNull);

    // Upcoming first line is dimmed: opacity ~0.5 and scaled to ~0.55.
    final firstLine = find.text('First line');
    expect(firstLine, findsWidgets);
    final opacity = t
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: firstLine,
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;
    expect(opacity, closeTo(0.5, 0.01));
    final scales = t
        .widgetList<Transform>(
          find.ancestor(of: firstLine, matching: find.byType(Transform)),
        )
        .map((w) => w.transform.storage[0])
        .toList();
    expect(scales, isNotEmpty);
    expect(scales.reduce((a, b) => a < b ? a : b), closeTo(0.55, 0.02));

    // Mini-player lyric stays hidden until the first cue.
    AnimatedOpacity miniOpacity() => t.widget<AnimatedOpacity>(
      find
          .descendant(
            of: find.byKey(const ValueKey('lyric')),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(miniOpacity().opacity, 0);

    // Wheel over the lyrics does not throw (anchorRow guards the -1 index).
    await t.sendEventToBinding(
      PointerScrollEvent(
        position: t.getCenter(firstLine),
        scrollDelta: const Offset(0, -40),
      ),
    );
    await _frames(t);
    expect(t.takeException(), isNull);

    // After the first cue the mini-player lyric appears.
    engine.at(6);
    await _frames(t);
    expect(app.lyricIndex, 0);
    expect(miniOpacity().opacity, 1);
    // Flush the debounced player-state save scheduled by the position change.
    await t.pump(const Duration(seconds: 3));
  });
}
