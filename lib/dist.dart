// Distribution track configuration.
// Keeps track-specific repository endpoints, URLs, and About UI labels.

import 'l10n/l10n.dart';

abstract final class DistConfig {
  /// Whether this build targets the GitLab distribution track.
  /// Controlled at compile-time via `--dart-define=YPM_DIST_GITLAB=true` or defaults to false on this track.
  static const bool isGitLab = bool.fromEnvironment('YPM_DIST_GITLAB', defaultValue: false);

  /// Upstream reference project by qier222.
  static const String upstreamRepoUrl = 'https://github.com/qier222/YesPlayMusic';

  /// Enhanced Edition repository identity for this track.
  static const String repo = 'workbydivyanshu/YesPlayMusic';
  static const String repoPage = 'https://github.com/$repo';
  static const String releasesPage = 'https://github.com/$repo/releases';

  /// Dynamic API endpoint for fetching release metadata.
  static Uri get latestReleaseUri => Uri.parse(
        'https://api.github.com/repos/$repo/releases/latest',
      );

  /// Sparkle / WinSparkle appcast feed URL.
  static String appcastUrl(String fileName) =>
      'https://github.com/$repo/releases/latest/download/$fileName';

  /// Documentation URL for plugin developers.
  static String get docsUrl =>
      'https://github.com/$repo/blob/main/docs/plugins.md';

  /// Section title in Settings → About.
  static String repositoryTitle(AppLocalizations l) =>
      l.localeName.startsWith('zh') ? '项目仓库' : 'Repository';

  /// Label for upstream repository button.
  static String upstreamLabel(AppLocalizations l) =>
      l.localeName.startsWith('zh') ? '原版 (qier222)' : 'Original (qier222)';

  /// Label for our enhanced repository button.
  static String enhancedLabel(AppLocalizations l) =>
      l.localeName.startsWith('zh') ? '✨ 增强版' : '✨ Enhanced Edition';

  /// Subtitle hint in Settings → About.
  static String sourceHint(AppLocalizations l) =>
      l.localeName.startsWith('zh')
          ? '原版仓库与增强版源码、发布版本'
          : 'Original repository, enhanced source code & releases';
}
