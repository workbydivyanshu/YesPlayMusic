import 'package:flutter_test/flutter_test.dart';
import 'package:yesplaymusic/data.dart';
import 'package:yesplaymusic/music/models.dart' as m;
import 'package:yesplaymusic/state.dart';

Track _t(String id) => Track.of(
  m.Track(id: id, name: 'Song $id', source: 'nosrc', duration: 180000),
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 350));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState app;
  setUp(() {
    app = AppState();
    app.clearQueue();
    if (app.shuffle) app.toggleShuffle();
  });
  tearDown(() async {
    await _settle();
    app.dispose();
  });

  test('toggleRepeat cycles all -> one -> off -> all', () {
    expect(app.repeatMode, RepeatMode.all);
    app.toggleRepeat();
    expect(app.repeatMode, RepeatMode.one);
    app.toggleRepeat();
    expect(app.repeatMode, RepeatMode.off);
    app.toggleRepeat();
    expect(app.repeatMode, RepeatMode.all);
  });

  test('repeat getter true for all/one, false for off', () {
    app.repeatMode = RepeatMode.all;
    expect(app.repeat, isTrue);
    app.repeatMode = RepeatMode.one;
    expect(app.repeat, isTrue);
    app.repeatMode = RepeatMode.off;
    expect(app.repeat, isFalse);
  });

  test('manual next() in RepeatMode.one advances at non-last index', () async {
    app.playList([_t('0'), _t('1'), _t('2')]);
    await _settle();
    expect(app.index, 0);
    app.repeatMode = RepeatMode.one;
    app.next();
    expect(app.index, 1);
  });

  test('setLyricsOffset / adjustLyricsOffset accumulate', () {
    expect(app.currentLyricsOffset, 0);
    app.adjustLyricsOffset(250);
    app.adjustLyricsOffset(250);
    expect(app.currentLyricsOffset, 500);
    app.adjustLyricsOffset(-1000);
    expect(app.currentLyricsOffset, -500);
    final key = app.track.key;
    app.setLyricsOffset(key, 1234);
    expect(app.currentLyricsOffset, 1234);
  });
}
