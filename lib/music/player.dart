// 播放引擎：把 Source 给出的 AudioStream 交给 libmpv（media_kit）播放。
//
// 本地文件是 file://，插件给的是 http(s)，可能带请求头（Referer、Cookie…），
// 对引擎来说没有区别。

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:media_kit/media_kit.dart' as mk;

import '../net/proxy.dart';
import 'eq.dart';
import 'models.dart';

/// The playback engine the app uses; tests swap in a fake without libmpv.
abstract interface class PlaybackEngine {
  abstract void Function(Duration)? onPosition, onDuration;
  abstract void Function(bool)? onPlaying;
  abstract void Function()? onCompleted;
  abstract void Function(String)? onError;
  abstract void Function(String key)? onAdvanced;
  String? get queuedKey;
  Duration get duration;
  Future<Duration> readDuration();
  Future<void> open(
    AudioStream s, {
    required String key,
    bool play = true,
    Duration? start,
    String rg = 'no',
    double gainDb = 0,
  });
  Future<void> queueNext(
    AudioStream s, {
    required String key,
    String rg = 'no',
    double gainDb = 0,
  });
  Future<void> dropQueued();
  Future<void> setReplayGain(String rg, double gainDb);
  Future<void> setEq(EqSettings s);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration d);
  Future<void> setVolume(double v);
  Future<void> setFade(double f);
  Future<void> stop();
  Future<void> dispose();
}

class AudioEngine implements PlaybackEngine {
  AudioEngine() {
    _subs = [
      _p.stream.position.listen((d) => onPosition?.call(d)),
      _p.stream.duration.listen((d) => onDuration?.call(d)),
      _p.stream.playing.listen((v) => onPlaying?.call(v)),
      _p.stream.completed.listen((done) {
        if (!done || _queuedKey != null) return;
        // media_kit restarts at playlist index 0 after EOF.
        _prunePlayedTracks().ignore();
        onCompleted?.call();
      }),
      _p.stream.error.listen((e) => onError?.call(e)),
      _p.stream.playlist.listen(_onPlaylist),
    ];
    // 网络音频走系统代理（本地文件不受影响）。
    final proxy = systemProxy();
    if (proxy != null && _p.platform is mk.NativePlayer) {
      (_p.platform as mk.NativePlayer).setProperty('http-proxy', proxy.url);
    }
    final n = _p.platform;
    if (n is mk.NativePlayer) {
      n.setProperty('prefetch-playlist', 'yes');
      // Lyrics are loaded by the app; stop mpv auto-loading sidecar .lrc files as subtitles.
      n.setProperty('sub-auto', 'no');
      n.onLoadHooks.add(_onLoad);
    }
  }

  /// 进程里调用一次，加载 libmpv。
  static void init() {
    mk.MediaKit.ensureInitialized();
    if (kDebugMode) _detachStalePlayers();
  }

  /// 热重启保护。mpv 的唤醒回调指向创建它的 isolate；热重启时旧 isolate
  /// 被销毁，mpv 核心线程再发事件（播放中每秒好几次）就跳进野指针崩溃
  /// （SIGSEGV/SIGBUS，栈在 mpv send_event / mp_client_send_property_changes）。
  ///
  /// 1. 挂一个 NativeFinalizer：isolate 销毁时 Dart VM 先跑 finalizer、再回收
  ///    回调跳板，C 里（native/mpv_guard.c）同步把所有 mpv 实例的回调清掉，
  ///    不留空窗。
  /// 2. 新 isolate 起来再清一遍，兜住没走到 finalizer 的情况。
  static void _detachStalePlayers() {
    try {
      final file = File(
        '${Directory.systemTemp.path}/'
        'com.alexmercerind.media_kit.NativeReferenceHolder.$pid',
      );
      if (!file.existsSync()) return;
      final address = int.tryParse(file.readAsStringSync().trim());
      if (address == null || address == 0) return;
      final buffer = Pointer<Void>.fromAddress(address);
      _mpvDetachAll(buffer);
      _mpvGuard.attach(_mpvGuardToken, buffer);
    } catch (_) {
      // 只是开发期的保护，找不到就算了
    }
  }

  static final _mpvGuard = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<Void>)>>(
      _mpvDetachAll,
    ),
  );

  /// 永远不释放，它的 finalizer 只会在 isolate 销毁时触发。
  static final _mpvGuardToken = _MpvGuardToken();

  final mk.Player _p = mk.Player(
    configuration: const mk.PlayerConfiguration(title: 'YesPlayMusic'),
  );
  late final List<StreamSubscription<Object?>> _subs;

  @override
  void Function(Duration)? onPosition, onDuration;
  @override
  void Function(bool)? onPlaying;

  /// 整个列表都播完了（后面没有排队的歌）。
  @override
  void Function()? onCompleted;
  @override
  void Function(String)? onError;

  /// mpv 自己切到 [queueNext] 排的那首；参数是它的 key。
  @override
  void Function(String key)? onAdvanced;

  /// 正在播放和排队歌曲的 key（open / queueNext 传进来的）。
  String? _currentKey, _queuedKey;
  @override
  String? get queuedKey => _queuedKey;

  @override
  Duration get duration => _p.state.duration;

  @override
  Future<Duration> readDuration() async {
    final n = _p.platform;
    if (n is! mk.NativePlayer) return Duration.zero;
    final value = await n.getProperty('duration', waitForInitialization: false);
    final seconds = double.tryParse(value);
    if (seconds == null || !seconds.isFinite || seconds <= 0) {
      return Duration.zero;
    }
    return Duration(microseconds: (seconds * 1000000).round());
  }

  /// 打开并（默认）开始播放，替换 mpv 的整个列表。[start] 恢复上次的进度。
  /// [rg] 和 [gainDb] 是这首的 ReplayGain，见 replay_gain.dart。
  @override
  Future<void> open(AudioStream s, {required String key, bool play = true,
      Duration? start, String rg = 'no', double gainDb = 0}) async {
    _currentKey = key;
    await _p.open(_media(s, key: key, start: start, rg: rg, gainDb: gainDb), play: play);
  }

  mk.Media _media(AudioStream s, {required String key, Duration? start,
      required String rg, required double gainDb}) {
    final uri = Uri.parse(s.url);
    // mpv 对 file:// 里的中文、空格等转义处理不一，直接给本地路径最稳。
    final target = uri.scheme == 'file' ? uri.toFilePath() : s.url;
    return mk.Media(target,
        httpHeaders: s.headers.isEmpty ? null : s.headers,
        start: start,
        extras: {'key': key, 'rg': rg, 'gain': gainDb});
  }

  void _onPlaylist(mk.Playlist pl) {
    if (pl.index <= 0 || pl.index >= pl.medias.length) return;
    final key = pl.medias[pl.index].extras?['key'];
    if (key is! String || key == _currentKey) return;
    _currentKey = key;
    if (_queuedKey == key) _queuedKey = null;
    onAdvanced?.call(key);
  }

  Future<void> _onLoad() async {
    final n = _p.platform;
    if (n is! mk.NativePlayer) return;
    try {
      final pos = int.tryParse(await n.getProperty('playlist-pos')) ?? -1;
      final ms = _p.state.playlist.medias;
      if (pos < 0 || pos >= ms.length) return;
      final x = ms[pos].extras;
      await n.setProperty('file-local-options/replaygain', '${x?['rg'] ?? 'no'}');
      final gain = (x?['gain'] as num?)?.toDouble() ?? 0;
      await n.setProperty('file-local-options/replaygain-fallback', gain.toStringAsFixed(2));
    } catch (_) {}
  }

  @override
  Future<void> queueNext(AudioStream s, {required String key,
      String rg = 'no', double gainDb = 0}) async {
    await dropQueued();
    await _prunePlayedTracks();
    _queuedKey = key;
    await _p.add(_media(s, key: key, rg: rg, gainDb: gainDb));
  }

  Future<void> _prunePlayedTracks() async {
    for (var i = _p.state.playlist.index - 1; i >= 0; i--) {
      await _p.remove(i);
    }
  }

  @override
  Future<void> dropQueued() async {
    if (_queuedKey == null) return;
    _queuedKey = null;
    final pl = _p.state.playlist;
    for (var i = pl.medias.length - 1; i > pl.index; i--) { await _p.remove(i); }
  }

  @override
  Future<void> setReplayGain(String rg, double gainDb) async {
    final n = _p.platform;
    if (n is! mk.NativePlayer) return;
    await n.setProperty('replaygain', rg);
    await n.setProperty('file-local-options/replaygain', rg);
    await n.setProperty('file-local-options/replaygain-fallback', gainDb.toStringAsFixed(2));
  }

  @override
  Future<void> setEq(EqSettings s) async {
    final prev = _eq; _eq = s; _preampDb = eqPreamp(s);
    await _applyVolume();
    final n = _p.platform;
    if (n is! mk.NativePlayer) return;
    if (prev.active && s.active) {
      final a = prev.gains, b = s.gains;
      for (var i = 0; i < eqBands.length; i++) {
        if (a[i] == b[i]) continue;
        await n.command(['af-command', eqLabel(i), 'g', b[i].toStringAsFixed(1)]);
      }
    } else if (prev.active != s.active || s.active) {
      await n.setProperty('af', eqFilter(s));
    }
  }

  EqSettings _eq = const EqSettings();
  double _preampDb = 0;
  double _fade = 1;
  double _volume = 1;

  @visibleForTesting
  Future<String> mpvProperty(String name) async {
    final n = _p.platform;
    if (n is! mk.NativePlayer) return '';
    return n.getProperty(name);
  }

  @override
  Future<void> play() => _p.play();
  @override
  Future<void> pause() => _p.pause();
  @override
  Future<void> seek(Duration d) => _p.seek(d);

  /// 0~1，滑块位置。
  @override
  Future<void> setVolume(double v) { _volume = v; return _applyVolume(); }

  @override
  Future<void> setFade(double f) { _fade = f.clamp(0.0, 1.0); return _applyVolume(); }
  Future<void> _applyVolume() => _p.setVolume(mpvVolume(_volume, gainDb: _preampDb, fade: _fade));

  /// 滑块位置 → mpv 的 volume（0~100）。
  ///
  /// 按分贝均匀的指数曲线（https://dr-lex.be/info-stuff/volumecontrols.html）：
  /// 幅度 = 10^(−[_rangeDb]·(1−p)/20)，滑块每走 10% 响度变化一样多；
  /// 最底下 10% 线性收到 0，拉到底是真正的静音。
  /// 范围没用文章推荐的 60 dB：系统音量本身已经压低了一截，60 dB 时下半段
  /// 全在 −30 dB 以下，听着都差不多小，用不上。
  /// mpv 自己会把 volume/100 再三次方（player/audio.c 的 audio_get_gain），
  /// 所以这里先开立方根抵消掉。
  static double mpvVolume(double p, {double gainDb = 0, double fade = 1}) {
    p = p.clamp(0.0, 1.0);
    double amp(double x) => math.pow(10, -_rangeDb * (1 - x) / 20).toDouble();
    var a = p < 0.1 ? p * 10 * amp(0.1) : amp(p);
    a *= math.pow(10, math.min(gainDb, 0) / 20) * fade.clamp(0.0, 1.0);
    return 100 * math.pow(a.clamp(0.0, 1.0), 1 / 3).toDouble();
  }

  /// 滑块从底到顶的响度范围（dB）。
  static const _rangeDb = 40.0;

  @override
  Future<void> stop() async { _currentKey = null; _queuedKey = null; await _p.stop(); }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _p.dispose();
  }
}

final class _MpvGuardToken implements Finalizable {}

@Native<Void Function(Pointer<Void>)>(
  symbol: 'ypm_mpv_detach_all',
  assetId: 'package:yesplaymusic/qjs',
)
external void _mpvDetachAll(Pointer<Void> buffer);
