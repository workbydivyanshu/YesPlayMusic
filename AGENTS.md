# YesPlayMusic Upstream Sync & Engineering Guidelines

This repository is YesPlayMusic (maintained by Vianca). Its upstream source bench is `https://github.com/qier222/YesPlayMusic`.
Aubade-grade engineering standards apply across all platform, framework, and plugin layers.

**Never merge or cherry-pick upstream commits into this repository.**
Sync by inspecting upstream diffs and adapting relevant, verified hunks cleanly to our codebase.

---

## 1. Upstream Sync Protocol

1. **Baseline Marker**:
   - The current reviewed upstream baseline marker is **`bb8912f`**.
   - The next pending sync batch is `bb8912f..de9997d` (31 commits).
2. **Commit Triage Matrix**:
   - **SKIP (Unconditional)**:
     - Telemetry & analytics (e.g. `lib/analytics.dart`, GA4 tokens, external tracking endpoints).
     - Upstream landing page deployments (`landing/`, Cloudflare Workers).
     - Upstream PR auto-close workflows or author-specific release infrastructure.
     - Commits reverting English localization back to Chinese-only.
   - **PORT**:
     - Core audio engine stability, gapless playback, and performance improvements.
     - Linux runner and window management hardening.
     - Plugin sandboxing, symlink security guards, and timeout isolation.
     - Localization improvements (translated and aligned to our ARB catalogs).
   - **ADAPT**:
     - Player or Now Playing features that touch shared UI surfaces. Must preserve the Aubade multi-source lyrics engine, single-track repeat mode, and desktop layout ergonomics.
3. **Branch & Release Flow**:
   - All ports and new features land on the **`mainline` branch first**.
   - Verification gate:
     - `flutter analyze --no-fatal-infos` (0 issues).
     - `flutter test` (all tests passing, currently 291+).
     - `readelf -d` on Linux runner verifying `libgcc_s.so.1` precedes `libflutter_linux_gtk.so`.
     - Standalone AppImage build and packaging verification.
   - Fast-forward merge `mainline` → `main`.
   - Update `AGENTS.md` marker and release notes.

---

## 2. Inviolable Core Architecture Rules

* **Zero-Telemetry Policy**:
  - Telemetry is permanently disabled. No GA4 Measurement Protocol tokens, no Google Analytics pings, no user tracking.
  - `Analytics` in `lib/analytics.dart` is a strict, no-op service. Never re-introduce background telemetry timers or sockets.
* **Full English UI & Multi-Lingual ARB Support**:
  - All user-facing UI labels, tooltips, dialogs, and errors must render in English by default.
  - When introducing new UI text, always add typed localization keys across all 9 ARB message catalogs (`app_en.arb`, `app_zh.arb`, `app_zh_Hant.arb`, `app_de.arb`, `app_es.arb`, `app_fr.arb`, `app_ja.arb`, `app_ko.arb`, `app_ru.arb`) and regenerate via `flutter gen-l10n`.
  - Headless unit tests (`test/`) that assert specific legacy strings use `lookupAppLocalizations(const Locale('zh'))` as an explicit test seam.
* **Aubade Multi-Source Lyrics Engine**:
  - Preserve `lib/lyrics/lyrics_models.dart`, `lyrics_providers.dart`, and `lyrics_repository.dart`.
  - All 6 online providers (Apple Music, Lrc.Red, BetterLyrics, Kugou, LRCLIB, Musixmatch) + local sidecar fallback must remain functional with 4s preferred word-sync race.
  - Per-track persistent timing offsets (`lyricsOffsets` in `prefs.json`) and Now Playing lyrics control popover must be maintained.
* **Linux Platform Native Citizenship**:
  - Runner CMake: `--no-as-needed,-lgcc_s` linker options must precede `flutter_linux_gtk` in `linux/runner/CMakeLists.txt` to prevent LuaJIT/libmpv SIGSEGV.
  - Window state: JSON persistence in `~/.config/yesplaymusic/window_state.json` with 500ms debounce, destroy cleanup, and display workarea clamping via GTK monitor API.
  - Packaging: AppImage packaged with relative library symlinks, `${LD_LIBRARY_PATH:-}` safe wrapper expansion, and installed to `~/Applications/YesPlayMusic-<version>-x86_64.AppImage`.

---

## 3. Shipped Wave History

| Wave | Commits | Key Deliverables |
|---|---|---|
| **Wave 01** | `a51dda2`, `b1c803b`, `7226b1b` | Linux LuaJIT SIGSEGV fix, window geometry persistence, Linux AppImage packaging workflow |
| **Wave 02** | `5259593`, `85157ad`, `9306d17` | AppImage headless CI hardening, maximized window bounds guard & 500ms I/O debounce, album shelf virtualization |
| **Wave 03** | `19e15e7`, `174e3ab`, `aa92d54` | Album shelf NaN edge-scroll crash fix, 3-state RepeatMode (`off`, `all`, `one`), unmaximized dimension preservation |
| **Wave 04** | `33316a7`, `35e8ed6`, `89c5489` | Aubade multi-source lyrics engine (6 providers, sanitizers, LRU cache, word-sync race), persistent timing offset, lyrics control popover, plain lyrics fallback |
| **Hardening** | `241b5b4`, `1373a9a`, `3d3e337`, `c5ad2f6` | English docs & localization, AppRun variable fix, sidebar logo in-app navigation, complete Google Analytics telemetry purge |
| **Audit & Fix** | `6c2be7d`, `6a7334a`, `957dd7c` | Window workarea clamp on monitor disconnect, timer use-after-free fix on destroy, 39 regression tests added (291 passed) |
| **Wave 05** | `9570908`, `e0bc52d`, `60c7fd6` | Symlink security guard on plugin install, dark GTK theme preference & keepRunning channel, settings nav overflow & locale storage sizes |
| **Wave 06** | `48840dc`, `bdba2fa`, `451ca0e` | Per-folder background isolate scanner with 30s watchdog & cancel, plugin conflict handling & auto-updates, coverflow library tab & mini-lyric persistence (310 tests) |
| **Wave 07** | `06a9e30`, `2a3fe9c`, `debccb5` | Gapless playback in mpv, 10-band ISO Equalizer & ReplayGain, Sleep timer with 20s fade-out, Now Playing card deck cover animation & RGB background fade (331 tests) |
| **Wave 08** | `397af25`, `9110b2f`, `44a4900` | Plugin scrobbling & playback events, local IPC socket/pipe sandbox, WebDAV official plugin, scoped host.files, Test Connection probe (341 tests) |

---

## 4. Standard Verification Commands

```bash
# 1. Static analysis (must be 0 issues)
flutter analyze --no-fatal-infos

# 2. Automated test suite (all 291+ tests must pass)
flutter test

# 3. Release build verification
flutter build linux --release

# 4. AppImage packaging & local installation
bash linux/packaging/build_appimage.sh build/linux/x64/release/bundle dist 3.0.1
cp dist/YesPlayMusic-3.0.0-x86_64.AppImage ~/Applications/YesPlayMusic-3.0.1-x86_64.AppImage.new
chmod +x ~/Applications/YesPlayMusic-3.0.1-x86_64.AppImage.new
mv -f ~/Applications/YesPlayMusic-3.0.1-x86_64.AppImage.new ~/Applications/YesPlayMusic-3.0.1-x86_64.AppImage
```
