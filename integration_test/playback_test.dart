// 在真机（macOS）上跑真实的 libmpv：flutter test integration_test -d macos
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:yesplaymusic/music/local/local_source.dart';
import 'package:yesplaymusic/music/models.dart';
import 'package:yesplaymusic/music/player.dart';
import 'package:yesplaymusic/music/source.dart';

/// 440Hz 正弦波 WAV，音量很小。
void sineWav(String path, int ms) {
  const rate = 22050;
  final n = rate * ms ~/ 1000;
  final b = ByteData(44 + n * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setInt16(
      44 + i * 2,
      (math.sin(2 * math.pi * 440 * i / rate) * 800).round(),
      Endian.little,
    );
  }
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(b.buffer.asUint8List());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  AudioEngine.init();

  // 从本地源取到 file:// 地址，交给引擎真的播放：进度会前进，播完会触发 completed。
  // 路径里带中文和空格，确认 file:// 转本地路径没问题。
  // 不用 testWidgets：本机开着辅助功能时，它会因为系统的 SemanticsHandle 报错。
  test('plays a local file to the end', () async {
    final tmp = Directory.systemTemp.createTempSync('ypm_play_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    sineWav(p.join(tmp.path, '音乐 文件夹', 'Tone - 测试.wav'), 1500);

    final src = LocalSource(
      folders: [tmp.path],
      cacheDir: p.join(tmp.path, 'c'),
    );
    await src.scan();
    final sources = Sources()..add(src);
    final track = (await src.search('测试', SearchKind.tracks)).tracks.single;

    final engine = AudioEngine();
    addTearDown(engine.dispose);
    var maxPos = Duration.zero;
    final done = Completer<void>();
    final errors = <String>[];
    engine.onPosition = (d) => maxPos = d > maxPos ? d : maxPos;
    engine.onCompleted = () => done.isCompleted ? null : done.complete();
    engine.onError = errors.add;

    await (() async {
      await engine.setVolume(0.2);
      await engine.open(await sources.stream(track), key: 'tone');
      await done.future.timeout(const Duration(seconds: 10));
    })();

    expect(errors, isEmpty);
    expect(maxPos.inMilliseconds, greaterThan(1000));
  });

  // 歌词由 App 自己加载，禁止 mpv 自动把同名 .lrc 当字幕挂上来。
  test('suppresses mpv subtitle autoload', () async {
    final engine = AudioEngine();
    addTearDown(engine.dispose);

    final subAuto = await engine.mpvProperty('sub-auto');
    if (subAuto.isNotEmpty) {
      expect(subAuto, 'no');
    } else {
      // 非原生后端拿不到属性时，退回检查没有暴露任何字幕轨。
      final trackList = await engine.mpvProperty('track-list');
      expect(trackList.contains("'type': 'sub'"), isFalse);
      expect(trackList.contains('"type": "sub"'), isFalse);
    }
  });

  // 列表播到最后一首并 EOF 后，media_kit 会把播放头退回 index 0。
  // 这里在 completed 时剪掉已播过的曲目，再按播放应重放最后一首（B），而不是第一首（A）。
  test('replays the last track after gapless EOF', () async {
    final tmp = Directory.systemTemp.createTempSync('ypm_gap_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    sineWav(p.join(tmp.path, 'Alpha.wav'), 1200);
    sineWav(p.join(tmp.path, 'Beta.wav'), 400);

    final src = LocalSource(
      folders: [tmp.path],
      cacheDir: p.join(tmp.path, 'c'),
    );
    await src.scan();
    final sources = Sources()..add(src);
    final a = (await src.search('Alpha', SearchKind.tracks)).tracks.single;
    final b = (await src.search('Beta', SearchKind.tracks)).tracks.single;

    final engine = AudioEngine();
    addTearDown(engine.dispose);
    final errors = <String>[];
    engine.onError = errors.add;

    final advanced = Completer<void>();
    final firstDone = Completer<void>();
    final replayDone = Completer<void>();
    var completedCount = 0;
    engine.onAdvanced = (key) {
      if (key == 'B' && !advanced.isCompleted) advanced.complete();
    };
    engine.onCompleted = () {
      completedCount++;
      if (completedCount == 1) {
        if (!firstDone.isCompleted) firstDone.complete();
      } else if (completedCount == 2) {
        if (!replayDone.isCompleted) replayDone.complete();
      }
    };

    await engine.setVolume(0.2);
    await engine.open(await sources.stream(a), key: 'A');
    await engine.queueNext(await sources.stream(b), key: 'B');

    // A 播完自动进到 B（gapless）。
    await advanced.future.timeout(const Duration(seconds: 10));
    // B 播完触发 completed，同时剪掉已播的 A。
    await firstDone.future.timeout(const Duration(seconds: 10));

    // 剪枝是异步的，等它落定后列表里应只剩 B。
    var count = '';
    for (var i = 0; i < 20; i++) {
      count = await engine.mpvProperty('playlist-count');
      if (count == '1') break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(count, '1');

    // 再按播放：B 只有 400ms，应很快再次 completed；若错误地重放了 A（1200ms）则超时。
    await engine.play();
    await replayDone.future.timeout(const Duration(milliseconds: 900));

    expect(errors, isEmpty);
  });
}
