# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.0.1] - 2026-11-24

### Fixes & Enhancements

- **Linux Crash Fix**: Resolved SIGSEGV startup crash on Linux distributions caused by symbol collision between system LuaJIT and Flutter's bundled LLVM unwinder by linking `libgcc_s.so.1` ahead of the Flutter engine. ([#2532](https://github.com/qier222/YesPlayMusic/issues/2532))
- **Linux Window Geometry Persistence**: Restored and persisted window size, coordinates, and maximized state across launches (`~/.config/yesplaymusic/window_state.json`), with unmaximized dimension guard and 500ms write debouncing. ([#2526](https://github.com/qier222/YesPlayMusic/issues/2526))
- **Album Shelf Virtualization & Edge Safety**: Virtualized large album shelf rendering with sliding layout window (`[pos - 16 .. pos + 16]`); eliminated division-by-zero (0/0 = NaN) crash on boundary scroll. ([#2531](https://github.com/qier222/YesPlayMusic/issues/2531))
- **Single-Track Repeat Mode**: Added 3-state `RepeatMode` (`off` / `all` / `one`) cycling through Repeat All, Repeat One, and Repeat Off, with queue looping, UI dot badges, and 8-language localization with full ARB catalog synchronization. ([#2534](https://github.com/qier222/YesPlayMusic/issues/2534))
- **Multi-Source Lyrics Engine**:
  - Integrated 6-provider lyrics race engine (Apple Music, Lrc.Red, BetterLyrics, Kugou KRC, LRCLIB, Musixmatch) with word-sync race and 4-second head-start.
  - Added Now Playing lyrics source badge and control dialog (source switching, persistent `±0.25s` offset adjustments, manual query search, local `.lrc` file export).
  - Added smooth scroll plain-text lyrics fallback.
- **Packaging**: Added official standalone `.AppImage` build target and script for Linux.

## [3.0.0] - 2026-11-24

Initial release of YesPlayMusic rewritten in Flutter.

- Multi-platform support: macOS (Apple Silicon), Windows, and Linux.
- Local music: scan music folders, parse tags, embedded covers, and lyrics.
- Plugins: online music services provided by third-party plugins running in an isolated QuickJS sandbox with explicit permission declarations. See [Plugin Guide](docs/plugins.md).
- Plugin manager: 1-click installation for official plugins (Jellyfin, Emby, Plex, Subsonic), support for GitHub repository, Release, or .zip links, and local folder installation.
- Automatic plugin recovery: automatically restarts crashed plugins once and reports failure diagnostics in Settings.
- Dynamic navigation: Home, Explore, Search, Album, Artist, Playlist, and Comments dynamically served by the active music source.
- User profile: account details, play history charts, top artists, and user playlists (when supported by plugin).
- Library: Songs, Albums (record shelf), Playlists, Artists (bubbles), and 3D Coverflow browsing.
- Now Playing: synchronized lyrics and translations, play queue, and similar tracks.
- Smart prefetching: preloads audio URLs and lyrics for next track; offline audio caching for streamed tracks.
- Multi-language UI: Simplified Chinese, Traditional Chinese, English, Japanese, Korean, German, French, Spanish, Russian.
- System integration: macOS Control Center Now Playing, lock screen metadata, media key support, system proxy detection.
- Keyboard shortcuts: global navigation and player controls with input focus suppression.
- Accessibility: screen reader semantics for buttons, sliders, switches, and selection states.
- Auto-updates: macOS and Windows automatic update checks and installation; Linux update prompts in Settings.
- AI Assistant (MCP): built-in Model Context Protocol server enabling AI agents (Claude, Cursor) to search, control playback, and manage queues.
- Local logging: diagnostic logs written to local storage, accessible in Settings → About.
- Anonymous analytics: opt-out usage statistics in Settings → About.

[Unreleased]: https://github.com/workbydivyanshu/YesPlayMusic/compare/v3.0.1...HEAD
[3.0.1]: https://github.com/workbydivyanshu/YesPlayMusic/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/workbydivyanshu/YesPlayMusic/releases/tag/v3.0.0
