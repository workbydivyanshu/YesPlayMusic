import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yesplaymusic/dist.dart';
import 'package:yesplaymusic/l10n/l10n.dart';
import 'package:yesplaymusic/shell.dart';
import 'package:yesplaymusic/state.dart';
import 'package:yesplaymusic/theme.dart';

Widget _app(AppState state) => WidgetsApp(
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
                  initialEntries: [
                    OverlayEntry(builder: (_) => const Shell()),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

Future<void> _frames(WidgetTester t, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

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
  setUpAll(prepareEnv);

  test('DistConfig contracts on current distribution track', () {
    expect(DistConfig.upstreamRepoUrl, 'https://github.com/qier222/YesPlayMusic');
    expect(DistConfig.repo, 'workbydivyanshu/YesPlayMusic');
    expect(DistConfig.repoPage, 'https://github.com/workbydivyanshu/YesPlayMusic');
    expect(DistConfig.releasesPage, 'https://github.com/workbydivyanshu/YesPlayMusic/releases');
    expect(
      DistConfig.latestReleaseUri.toString(),
      'https://api.github.com/repos/workbydivyanshu/YesPlayMusic/releases/latest',
    );
  });

  testWidgets('Settings About tab renders both Original and Enhanced Edition buttons', (t) async {
    final app = AppState();
    addTearDown(() => app.dispose());

    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(_app(app));
    await _frames(t);

    app.open('/settings');
    await _frames(t);

    final about = find.text('关于');
    expect(about, findsOneWidget);
    await t.tap(about);
    await _frames(t);

    expect(find.text('原版 (qier222)'), findsOneWidget);
    expect(find.text('✨ 增强版'), findsOneWidget);
  });
}
