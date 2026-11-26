import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'playback_artwork.dart';
import 'state.dart';

/// 系统的「正在播放」：把当前歌曲告诉系统（控制中心、锁屏），并接住键盘上的
/// 媒体键和耳机按键。macOS 走 MPRemoteCommandCenter（原生代码在
/// MainFlutterWindow.swift）；其他平台还没有接，调用会静默失败。
class MediaSession {
  MediaSession(this.app);
  final AppState app;

  static bool get supportsMediaKeys => Platform.isMacOS || Platform.isWindows;

  static const _channel = MethodChannel('yesplaymusic/media');
  Timer? _drift;

  // 上次告诉系统的状态；系统按播放速度自己推算进度，只在变化或进度对不上时再发。
  String? _key;
  String? _cover;
  int _artworkRevision = 0;
  bool? _playing;
  bool? _island;
  double? _duration;
  double _sentPos = 0;
  DateTime _sentAt = DateTime(0);

  void attach() {
    if (!supportsMediaKeys) return;
    _channel.setMethodCallHandler(_onCommand);
    app.addListener(_sync);
    // 拖进度条、快进快退不一定会通知，每秒对一下进度
    _drift = Timer.periodic(const Duration(seconds: 1), (_) => _sync());
    _sync();
  }

  void detach() {
    if (!supportsMediaKeys) return;
    _drift?.cancel();
    app.removeListener(_sync);
    _channel.setMethodCallHandler(null);
    if (Platform.isWindows) {
      _key = null;
      _artworkRevision++;
      _send('clear');
    }
  }

  void _sync() {
    final t = app.track;
    if (Platform.isWindows && identical(t, Track.none)) {
      if (_key != null) {
        _key = null;
        _artworkRevision++;
        _send('clear');
      }
      return;
    }
    final pos = app.position;
    final duration = app.playbackDuration;
    final expected = _playing == true
        ? _sentPos + DateTime.now().difference(_sentAt).inMilliseconds / 1000
        : _sentPos;
    final trackChanged = t.key != _key;
    final artworkChanged =
        trackChanged || (Platform.isWindows && t.cover != _cover);
    if (!artworkChanged &&
        app.playing == _playing &&
        app.island == _island &&
        duration == _duration &&
        (pos - expected).abs() < 1.5) {
      return;
    }
    _key = t.key;
    _cover = t.cover;
    _playing = app.playing;
    _island = app.island;
    _duration = duration;
    _sentPos = pos;
    _sentAt = DateTime.now();
    _send('update', {
      'title': t.title,
      'artist': t.artist,
      'album': t.album,
      'duration': duration,
      'position': pos,
      'playing': app.playing,
      // Dynamic Island toggle (native code in DynamicIsland.swift)
      'island': app.island,
      if (Platform.isWindows) 'artworkChanged': artworkChanged,
      // 换歌时才重新取封面
      if (Platform.isMacOS && trackChanged) 'art': _art(t.cover),
    });
    if (Platform.isWindows && artworkChanged) {
      final revision = ++_artworkRevision;
      if (t.cover.isNotEmpty) unawaited(_loadArtwork(t.cover, revision));
    }
  }

  /// 系统只能取网络封面或本地文件。
  static String _art(String cover) =>
      cover.startsWith('http') || cover.startsWith('/') ? cover : '';

  Future<void> _loadArtwork(String cover, int revision) async {
    try {
      final bytes = await loadPlaybackArtwork(cover);
      if (revision == _artworkRevision) await _send('artwork', bytes);
    } catch (error) {
      if (revision == _artworkRevision) {
        debugPrint('Media artwork failed: ${error.runtimeType}');
      }
    }
  }

  Future<void> _send(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (error) {
      if (Platform.isWindows) debugPrint('SMTC $method failed: $error');
    }
  }

  Future<void> _onCommand(MethodCall call) async {
    switch (call.method) {
      case 'play':
        if (!app.playing) app.togglePlay();
      case 'pause':
        if (app.playing) app.togglePlay();
      case 'toggle':
        app.togglePlay();
      case 'next':
        app.next();
      case 'previous':
        app.prev();
      case 'seek':
        final s = (call.arguments as num?)?.toDouble() ?? 0;
        app.seekTo(s);
      case 'openNowPlaying':
        app.openNowPlaying();
    }
    _sync();
  }
}
