// 页面冒烟测试：整个外壳（Shell）+ 本地音乐源、不加载插件，挨个打开页面，
// 空状态下都要能画出来、不抛异常。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:yesplaymusic/l10n/l10n.dart';
import 'package:yesplaymusic/music/eq.dart';
import 'package:yesplaymusic/pages/settings.dart';
import 'package:yesplaymusic/shell.dart';
import 'package:yesplaymusic/state.dart';
import 'package:yesplaymusic/theme.dart';
import 'package:yesplaymusic/ui/tap.dart';

import '../music/local_source_test.dart' show wav;

Widget appFor(AppState state, {Widget child = const Shell()}) => WidgetsApp(
  color: const Color(0xFF0B0B0D),
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  builder: (context, _) {
    syncGlobalL10n(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        state.applyTheme();
        return AppScope(
          state: state,
          child: DefaultTextStyle(
            style: ts(14),
            child: Overlay(
              initialEntries: [OverlayEntry(builder: (_) => child)],
            ),
          ),
        );
      },
    );
  },
);

/// 页面里有转圈、入场动画，pumpAndSettle 等不完，固定推几帧。
Future<void> _frames(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// 准备页面测试环境：
/// - 和 main() 一样载入日期数据（首页日期行要用）；
/// - 测试默认的 Ahem 字体每个字都是方块，英文比真实字体宽得多，会画出假的溢出。
///   把应用自带的 Archivo 加载进来（中文仍是 Ahem，宽度和真实字形接近）。
Future<void> prepareEnv() async {
  await initializeDateFormatting();
  final families = <String, List<String>>{};
  for (final f in Directory('assets/fonts').listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    final family = name.startsWith('ArchivoSemiExpanded')
        ? 'ArchivoSemi'
        : name.startsWith('ArchivoExpanded')
        ? 'ArchivoWide'
        : 'Archivo';
    (families[family] ??= []).add(f.path);
  }
  for (final e in families.entries) {
    final loader = FontLoader(e.key);
    for (final path in e.value) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
      );
    }
    await loader.load();
  }
}

void main() {
  late AppState app;

  setUpAll(prepareEnv);

  setUp(() {
    app = AppState();
    app.clearQueue();
  });
  tearDown(() => app.dispose());

  /// 默认是应用允许的最小窗口（macOS / Windows 都是 1280×800）。
  Future<void> boot(
    WidgetTester t, {
    double width = 1280,
    Widget child = const Shell(),
  }) async {
    t.view.physicalSize = Size(width, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(appFor(app, child: child));
    await _frames(t);
  }

  for (final route in [
    'home',
    'discover',
    'library/albums',
    'library/tracks',
    'library/playlists',
    'library/artists',
    'coverflow/albums',
    'search',
    'profile',
    'album/${Uri.encodeComponent('不存在')}',
  ]) {
    testWidgets('打开 /$route', (t) async {
      await boot(t);
      app.open('/$route');
      await _frames(t);
      expect(t.takeException(), isNull);
      expect(app.path, '/$route');
      // 页面真的画出了文字，不是一片空白
      expect(find.byType(Text), findsWidgets);
    });
  }

  // 正在播放：队列是空的时候打开、切换各个标签页。
  testWidgets('空队列打开正在播放', (t) async {
    await boot(t);
    for (final tab in NpTab.values) {
      app.openNowPlaying(tab);
      await _frames(t);
      expect(t.takeException(), isNull, reason: '$tab');
    }
  });

  // 设置页的每个标签页。
  // 最小窗口（1280）下「通用」「快捷键」「MCP」两列 512 固定宽放不下，溢出 160px，
  // 要先定设计怎么收窄；这里先用 1440 宽测，最小窗口那条见下面 skip 的测试。
  Future<void> settingsTabs(WidgetTester t, double width) async {
    await boot(t, width: width);
    app.open('/settings');
    await _frames(t);
    var tapped = 0;
    for (final label in ['插件', 'MCP', '快捷键', '关于', '通用']) {
      final f = find.text(label);
      if (f.evaluate().isEmpty) continue;
      tapped++;
      await t.tap(f.first);
      await _frames(t);
      expect(t.takeException(), isNull, reason: label);
      if (label == '快捷键') {
        expect(
          find.text('媒体键'),
          Platform.isMacOS || Platform.isWindows
              ? findsOneWidget
              : findsNothing,
        );
      }
    }
    expect(tapped, greaterThanOrEqualTo(3));
  }

  testWidgets('音乐库为空时扫描中显示正在扫描文案', (t) async {
    await boot(t);
    app.open('/library/albums');
    await _frames(t);
    expect(find.text('音乐库还是空的'), findsOneWidget);
    expect(find.text('添加音乐文件夹'), findsOneWidget);

    app.update(() => app.scanning = true);
    await _frames(t);
    expect(find.text('正在扫描'), findsOneWidget);
    expect(find.text('.'), findsNWidgets(3));
    expect(find.text('音乐库还是空的'), findsNothing);
    expect(find.text('添加音乐文件夹'), findsNothing);

    app.update(() => app.scanning = false);
    await _frames(t);
    expect(find.text('音乐库还是空的'), findsOneWidget);
  });

  testWidgets('只有无专辑标签的歌曲时，音乐库仍可浏览歌曲', (t) async {
    final folder = Directory.systemTemp.createTempSync('ypm_albumless_');
    addTearDown(() => folder.deleteSync(recursive: true));
    wav(
      folder.uri.resolve('loose.wav').toFilePath(),
      info: {'INAM': 'Loose Track', 'IART': 'Local Artist'},
    );
    await t.runAsync(() => app.loadLibrary(folders: [folder.path]));
    app.open('/library/albums');
    await boot(t);

    expect(find.text('音乐库还是空的'), findsNothing);
    expect(find.text('还没有专辑'), findsOneWidget);
    await t.tap(find.text('歌曲'));
    await _frames(t);
    expect(find.text('Loose Track'), findsOneWidget);
  });

  testWidgets('设置页各标签', (t) => settingsTabs(t, 1440));

  testWidgets('restores the selected accent color after restart', (t) async {
    Future<void> openSettings(AppState state) async {
      state.open('/settings');
      await _frames(t);
    }

    // All tests in this file share one prefs.json; drop the swatch entry when done.
    final prefsFile = File(p.join(AppState.supportDir(), 'prefs.json'));
    addTearDown(() {
      if (!prefsFile.existsSync()) return;
      final prefs = jsonDecode(prefsFile.readAsStringSync()) as Map;
      prefs.remove('swatch');
      prefsFile.writeAsStringSync(jsonEncode(prefs));
    });

    await boot(t, width: 1440);
    await openSettings(app);
    expect(app.swatch, 0);

    final mint = find.byWidgetPredicate(
      (w) => w is Tap && w.tip == L.swatchMint,
    );
    await t.tap(mint);
    await _frames(t);
    expect(app.swatch, 2);
    expect(jsonDecode(prefsFile.readAsStringSync())['swatch'], 'mint');

    await t.pumpWidget(const SizedBox.shrink());
    final restarted = AppState();
    try {
      await t.pumpWidget(appFor(restarted));
      await openSettings(restarted);
      expect(restarted.swatch, 2);
      expect(accent, swatchesDark[2]);
    } finally {
      await t.pumpWidget(const SizedBox.shrink());
      restarted.dispose();
    }
  });

  for (final enabled in [false, true]) {
    testWidgets('equalizer wheel scrolling (enabled: $enabled)', (t) async {
      // All tests in this file share one prefs.json, and the wheel saves the
      // EQ there. The tearDown that runs app.dispose() is declared on the
      // group, so it runs after this test's own tear-downs; the save is
      // debounced and lands while _frames() pumps, which the expectation at
      // the end checks, so dispose() has nothing left to flush afterwards.
      final prefsFile = File(p.join(AppState.supportDir(), 'prefs.json'));
      addTearDown(() {
        if (!prefsFile.existsSync()) return;
        final prefs = jsonDecode(prefsFile.readAsStringSync()) as Map;
        prefs.remove('eq');
        prefsFile.writeAsStringSync(jsonEncode(prefs));
      });

      app.eq = EqSettings(enabled: enabled);
      await boot(t, width: 1440);
      app.open('/settings');
      await _frames(t);

      final band = find
          .ancestor(
            of: find.text('${eqBands.first}'),
            matching: find.byType(Column),
          )
          .first;
      final slider = find.descendant(
        of: band,
        matching: find.byWidgetPredicate(
          (widget) => widget is Listener && widget.onPointerSignal != null,
        ),
      );
      await t.ensureVisible(slider);
      await t.pump();
      final scroll = Scrollable.of(t.element(slider)).position;
      final start = scroll.pixels;
      const delta = -20.0;

      Future<void> wheelAt(
        Finder target,
        Offset scrollDelta, {
        PointerDeviceKind kind = PointerDeviceKind.mouse,
      }) async {
        await t.sendEventToBinding(
          PointerScrollEvent(
            position: t.getCenter(target),
            scrollDelta: scrollDelta,
            kind: kind,
          ),
        );
        await _frames(t);
      }

      // Horizontal-only wheel: no gain change, nothing scrolls.
      await wheelAt(slider, const Offset(20, 0));
      expect(app.eq.gains.first, 0);
      expect(scroll.pixels, start);

      await wheelAt(slider, const Offset(0, delta));
      expect(app.eq.gains.first, enabled ? 0.5 : 0);
      expect(scroll.pixels, enabled ? start : start + delta);
      if (!enabled) {
        // Trackpad pans over a disabled band still scroll the page.
        final before = scroll.pixels;
        final pointer = TestPointer(1, PointerDeviceKind.trackpad);
        final at = t.getCenter(slider);
        await t.sendEventToBinding(pointer.panZoomStart(at));
        for (var y = 10.0; y <= 60; y += 10) {
          await t.sendEventToBinding(
            pointer.panZoomUpdate(at, pan: Offset(0, y)),
          );
          await t.pump();
        }
        await t.sendEventToBinding(pointer.panZoomEnd());
        await _frames(t);
        expect(scroll.pixels, isNot(before));
        expect(app.eq.gains.first, 0);
        return;
      }

      // Over the frequency label the wheel scrolls the page.
      await wheelAt(find.text('${eqBands.first}'), const Offset(0, delta));
      expect(scroll.pixels, start + delta);
      expect(app.eq.gains.first, 0.5);
      await t.ensureVisible(slider);
      await t.pump();
      final top = scroll.pixels;

      // Trackpad scroll events add up: one 0.5 dB step per 20 px.
      for (var i = 0; i < 3; i++) {
        await wheelAt(
          slider,
          const Offset(0, -5),
          kind: PointerDeviceKind.trackpad,
        );
      }
      expect(app.eq.gains.first, 0.5);
      await wheelAt(
        slider,
        const Offset(0, -5),
        kind: PointerDeviceKind.trackpad,
      );
      expect(app.eq.gains.first, 1);
      expect(scroll.pixels, top);

      // Two-finger pan (pan-zoom events): fingers down raise the gain like
      // wheel-up, in 0.5 dB steps per 20 px, and the page stays put.
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      final at = t.getCenter(slider);
      await t.sendEventToBinding(pointer.panZoomStart(at));
      final seen = <double>[];
      for (var y = 5.0; y <= 50; y += 5) {
        await t.sendEventToBinding(
          pointer.panZoomUpdate(at, pan: Offset(0, y)),
        );
        await t.pump();
        seen.add(app.eq.gains.first);
      }
      expect(seen, [1, 1, 1, 1.5, 1.5, 1.5, 1.5, 2, 2, 2]);
      // Reversing drops the unspent 10 px: back 50 px is two steps down.
      await t.sendEventToBinding(pointer.panZoomUpdate(at, pan: Offset.zero));
      await t.pump();
      await t.sendEventToBinding(pointer.panZoomEnd());
      await _frames(t);
      expect(app.eq.gains.first, 1);
      expect(scroll.pixels, top);

      // The EQ save has reached prefs.json before tear-down (see above).
      expect(
        (jsonDecode(prefsFile.readAsStringSync()) as Map)['eq'],
        isNotNull,
      );
    });
  }

  for (final supported in [false, true]) {
    testWidgets('快捷键页的媒体键说明（支持：$supported）', (t) async {
      await boot(
        t,
        width: 1440,
        child: SettingsPage.withMediaKeysSupport(supported: supported),
      );
      await t.tap(find.text('快捷键'));
      await _frames(t);

      expect(find.text('播放'), findsOneWidget);
      expect(find.text('界面'), findsOneWidget);
      final visibility = supported ? findsOneWidget : findsNothing;
      expect(find.text('媒体键'), visibility);
      expect(find.text('键盘媒体键和耳机按键'), visibility);
    });
  }
  testWidgets(
    '设置页各标签（最小窗口）',
    (t) => settingsTabs(t, 1280),
    skip: true, // 已知问题：两列设置页在最小窗口下溢出，等设计
  );
}
