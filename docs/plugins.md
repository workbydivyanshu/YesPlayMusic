# Plugin Development Guide

YesPlayMusic does not include built-in online music services. Beyond local audio playback, all music sources are provided by plugins. A plugin is a directory containing a `plugin.json` manifest and an ES module JavaScript bundle. The application executes plugins within an embedded QuickJS engine; the app dynamically surfaces features based on the functions exported by the plugin.

The plugin protocol adopts the MyGo Music specification, allowing existing MyGo plugins to be ported with minimal changes.

> **Security Notice**: Plugins can access declared network hosts, read and write their own data directories, and, when explicitly granted by the user, launch local binaries. Only install plugins from trusted sources. For details, see [SECURITY.md](../SECURITY.md).

---

## Table of Contents

- [Quick Start](#quick-start)
- [Plugin Directories](#plugin-directories)
- [Installing Plugins](#installing-plugins)
- [plugin.json](#pluginjson)
- [Runtime Environment](#runtime-environment)
- [Host API](#host-api)
- [Exported Functions](#exported-functions)
- [Data Structures](#data-structures)
- [Error Handling](#error-handling)
- [Caching](#caching)
- [Resource Limits](#resource-limits)
- [Debugging](#debugging)

---

## Quick Start

Create a directory named `hello` with two files:

`plugin.json`
```json
{
  "id": "hello",
  "name": "Hello",
  "version": "0.1.0",
  "minAppVersion": "3.0.0",
  "main": "index.js",
  "permissions": { "network": ["example.com"] }
}
```

`index.js`
```js
const tracks = [
  {
    id: "1",
    name: "Hello World",
    artists: [{ id: "a1", name: "Example Artist" }],
    album: { id: "al1", name: "Example Album", imageUrl: "https://example.com/cover.jpg" },
    duration: 180000,
  },
];

export async function search({ query }) {
  return { tracks: tracks.filter((t) => t.name.toLowerCase().includes(query.toLowerCase())) };
}

export async function stream({ id }) {
  return { url: `https://example.com/audio/${id}.mp3`, type: "mp3" };
}
```

Place the folder into the plugins directory (Settings → Plugins → **Open Plugins Directory**). Click **Reload**, select the plugin under Settings → Plugins → **Music Source** (or click the avatar in the lower left corner), and you can search for and play the track.

---

## Plugin Directories

| Operating System | Plugins Directory | Plugin Data Directory |
| --- | --- | --- |
| macOS | `~/Library/Application Support/YesPlayMusic/plugins/<id>/` | `~/Library/Application Support/YesPlayMusic/plugin-data/<id>/` |
| Windows | `%APPDATA%\YesPlayMusic\plugins\<id>\` | `%APPDATA%\YesPlayMusic\plugin-data\<id>\` |
| Linux | `$XDG_DATA_HOME/YesPlayMusic/plugins/<id>/` (default `~/.local/share/...`) | `$XDG_DATA_HOME/YesPlayMusic/plugin-data/<id>/` |

During development, you can symlink your workspace into the plugins directory. Directories starting with `.` are ignored.

---

## Installing Plugins

Navigate to Settings → Plugins → **Install Plugin**, and paste one of the following URL formats:

| URL Format | Resolution |
| --- | --- |
| `github.com/owner/repo` or `owner/repo` | Latest Release `.zip` asset; if none, release source tarball; if no release, default branch code |
| `github.com/owner/repo/releases/tag/v1.2.0` | Exact release package |
| `github.com/owner/repo/tree/branch/subpath` | Exact subdirectory under specified branch/tag/commit |
| `github.com/owner/repo/blob/branch/.../plugin.json` | Directory containing the specified `plugin.json` |
| URLs ending in `.zip` | Downloaded, extracted, and resolved to the top-level directory containing `plugin.json` |
| URLs ending in `plugin.json` | Downloads the manifest, the `main` module, and relative imports |

You can also click **Install from local folder...** to select any directory containing a `plugin.json`.

Before installation, the application displays the requested permissions and discovered capabilities (parsed statically from `export` declarations without executing plugin code). If `minAppVersion` exceeds the current application version, installation is blocked. Re-installing an existing ID replaces the code while preserving `plugin-data/<id>/` storage and settings.

Plugin data directory contents:
- `storage.json`: Key-value store written by `host.storage`.
- `settings.json`: User configurations saved from the plugin settings dialog.

---

## plugin.json

```json
{
  "id": "example",
  "name": "Example",
  "version": "1.0.0",
  "description": "An example plugin.",
  "author": "Example",
  "icon": "icon.png",
  "minAppVersion": "3.0.0",
  "main": "index.js",
  "playback": "stream",
  "permissions": {
    "network": ["api.example.com", "*.example-cdn.net", "{setting:server}"],
    "process": ["yt-dlp"]
  },
  "settings": [
    { "key": "server", "label": "Server URL", "help": "e.g. http://127.0.0.1:4533" },
    { "key": "token", "label": "Token", "type": "password", "link": "https://example.com/token" },
    { "key": "hq", "label": "High Quality", "type": "boolean" },
    {
      "key": "quality",
      "label": "Quality",
      "type": "select",
      "options": [
        { "value": "", "label": "Follow Player" },
        { "value": "lossless", "label": "Lossless" }
      ]
    }
  ],
  "navigation": [{ "builtin": "home" }, { "builtin": "liked" }, { "title": "Charts", "page": "charts" }]
}
```

| Field | Required | Description |
| --- | --- | --- |
| `id` | Yes | Lowercase letters, numbers, and `._-`, max 64 chars. `local` is reserved. |
| `name` | Yes | Display name shown in UI. |
| `version` | No | Semantic version string. |
| `description` | No | Short description shown in cards and install modals. |
| `author` | No | Author string or `{ "name": "..." }`. |
| `icon` | No | Square image (`.png`, `.jpg`, `.webp`, 256×256 recommended). Defaults to initials. |
| `minAppVersion` | No | Minimum application version required (e.g. `3.0.0`). |
| `main` | No | Entry point module (defaults to `index.js`). |
| `playback` | No | `stream` (default, audio played by app) or `remote` (remote playback control). |
| `permissions.network` | No | Allowed network hosts for `fetch`. |
| `permissions.process` | No | Allowed host executable names/paths for `host.spawn`. `true` equals `["*"]`. |
| `settings` | No | Configurable parameters shown in plugin settings modal. Values are stored as strings. Supported types: `text` (default), `password`, `boolean`, `select`. |
| `navigation` | No | Sidebar entries: `{ "builtin": "home" \| "liked" \| "savedAlbums" \| "stations" \| "shows" }` or `{ "title", "page", "icon" }` pointing to `browse(page)`. |

### Network Permissions

| Syntax | Match Behavior |
| --- | --- |
| `api.example.com` | Matches exact host |
| `*.example.com` | Matches subdomains (excludes root `example.com`) |
| `{setting:server}` | Dynamically matches host from the `server` setting parameter |
| `*` | Matches any host (discouraged) |

HTTP redirects to undeclared hosts are blocked.

---

## Runtime Environment

- Plugins execute in [QuickJS-ng](https://github.com/quickjs-ng/quickjs) with ES2023 and ES module support.
- No Node.js runtime, DOM, or `std`/`os` modules. File system access and process creation are sandboxed.
- Each plugin runs on an isolated background worker thread.

### Available Globals

| Global | Description |
| --- | --- |
| `fetch`, `Headers`, `Response` | Standard Fetch API. `Response` supports `.text()`, `.json()`, `.bytes()`, `.arrayBuffer()`. Requests inherit system proxy settings. Cross-origin redirects strip sensitive headers (`Authorization`, `Cookie`). |
| `URL`, `URLSearchParams` | Standard URL utilities. |
| `TextEncoder`, `TextDecoder` | UTF-8 encoding and decoding. |
| `AbortController`, `AbortSignal` | Includes `AbortSignal.timeout(ms)`. |
| `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval` | Standard timers. |
| `console.log/info/warn/error/debug` | Outputs formatted messages to application stdout with `[plugin <id>]` prefix. |
| `atob`, `btoa` | Base64 utilities. |
| `host` | Application capability bridge. |

---

## Host API

| Method / Property | Description |
| --- | --- |
| `host.platform` | Operating system: `'darwin'`, `'windows'`, or `'linux'`. |
| `host.arch` | CPU architecture: `'arm64'`, `'amd64'`, etc. |
| `host.dir` | Absolute path to plugin directory. |
| `host.dataDir` | Absolute path to plugin persistent data directory. |
| `host.storage.get(key)` / `.set(key, val)` / `.remove(key)` | Synchronous JSON storage stored in `storage.json`. |
| `host.setting(key)` | Reads current setting value as configured by user. |
| `host.language()` | Current application locale (e.g. `'en'`, `'zh-CN'`, `'ja'`). |
| `host.t(text)` | Localizes string using `locales/<lang>.json` in plugin directory with fallback prefix matching. |
| `host.openURL(url)` | Opens HTTP/HTTPS URL in default web browser. |
| `host.crypto.md5(text)` | Computes MD5 hash as hex string. |
| `host.crypto.aesEcbEncrypt(key, text)` | AES-128-ECB + PKCS7 encryption, returns hex string. |
| `host.signInPrompt({ qr, text })` | Displays QR code or instructions inside app login dialog. |
| `host.webSignIn({ url, cookiesOf, until, userAgent })` | Opens isolated ephemeral webview dialog; captures specified cookies upon matching `until` condition (macOS only). |
| `host.spawn(command, args)` | Launches allowed local executable. |

### Process Execution (`host.spawn`)

Requires:
1. `command` matched in `permissions.process`.
2. User explicitly enabled **Allow running local programs** in plugin options.

Returns process handle:
- `pid`: Process ID.
- `write(text)` / `closeStdin()`: Standard input control.
- `readLine()`: Reads a line from stdout (returns Promise resolving to string or `null`).
- `wait()`: Awaits process exit (returns exit code).
- `errorOutput()`: Captured stderr output.
- `kill()`: Terminates process.

---

## Exported Functions

Plugins export functions via standard ES module `export`. Functions receive a parameters object and may be `async`.

### Authentication & Profile
- `account()`: Returns `Account | null`. Called on app launch and plugin activation.
- `signIn()`: Handles interactive login (up to 10 min timeout for QR/web flows).
- `signOut()`: Clears credentials and active session.
- `profile()`: Returns `Profile` model for profile view.

### Discovery & Search
- `home()`: Returns `Browse` structure for Home view.
- `browse({ page })`: Returns `Browse` structure for custom sections or explore pages.
- `search({ query, kind, offset })`: Returns `SearchResult`. `kind` can be `tracks`, `albums`, `artists`, `playlists`, `shows`.
- `suggest({ query })`: Returns string array for search query autocomplete.
- `hotSearches()`: Returns trending search keywords.

### Library & Collection
- `library({ kind, offset })`: Comprehensive catalog for self-hosted libraries.
- `liked({ offset })`: Liked tracks page.
- `isLiked({ ids })`: Map or array of liked boolean states.
- `like({ id, on })`: Toggle track like status.
- `savedAlbums({ offset })`: Saved album collection.
- `saveAlbum({ id, on })`: Toggle album save status.
- `followArtist({ id, on })`: Toggle artist follow status.
- `recent()`: Returns recently played tracks.
- `played({ id })`: Scrobble / play count notification.

### Playback & Metadata
- `stream({ id, quality })`: Returns `AudioStream` containing audio playback URL and HTTP headers.
- `lyrics({ id })`: Returns synchronized LRC or syllable-timed `Lyrics`.
- `similar({ id })`: Returns related recommendations for Now Playing page.
- `station({ id, seed })`: Fetches subsequent batch of tracks for radio station.
- `dislike({ id, station })`: Marks track as disliked.

---

## Data Structures

```ts
type Artist = { id: string; name: string; imageUrl?: string; following?: boolean };

type Album = {
  id: string; name: string; imageUrl?: string; artists?: Artist[];
  released?: string;
  kind?: "album" | "single" | "ep" | "compilation";
  trackCount?: number; saved?: boolean;
  added?: string;
  copyright?: string;
};

type Track = {
  id: string; name: string; artists?: Artist[]; album?: Album;
  duration?: number;
  url?: string;
  unavailable?: boolean;
  added?: string;
};

type Playlist = {
  id: string; name: string; imageUrl?: string; description?: string;
  owner?: string; subtitle?: string; trackCount?: number; plays?: number;
  mine?: boolean;
  saved?: boolean;
  fixed?: boolean;
  tracks?: Track[];
};

type Account = { id: string; name: string; imageUrl?: string };

type SearchResult = {
  tracks?: Track[]; albums?: Album[]; artists?: Artist[]; playlists?: Playlist[];
  more?: boolean; total?: number;
};

type TrackPage = { tracks: Track[]; more?: boolean };

type AudioStream = {
  url: string;
  type?: string;
  quality?: string; bitRate?: number; size?: number;
  headers?: Record<string, string>;
};

type Lyrics = {
  lrc?: string;
  translation?: string;
  lines?: {
    start: number;
    end?: number;
    text?: string;
    translation?: string;
    words?: { start: number; end: number; text: string }[];
  }[];
};

type Browse = {
  title?: string; subtitle?: string; imageUrl?: string; description?: string;
  sections: Section[];
  tabs?: Choice[];
  filters?: Choice[][];
};

type Section = {
  title?: string; subtitle?: string;
  style?: "modes" | "shelf" | "songs" | "charts" | "grid";
  tracks?: Track[]; albums?: Album[]; artists?: Artist[]; playlists?: Playlist[];
  modes?: Mode[];
  morePage?: string;
  empty?: string;
};
```

---

## Error Handling

Throw an Error object with an attached `code` property:

```js
const err = new Error("Please sign in first");
err.code = "signIn";
throw err;
```

| Error Code | Meaning | App Behavior |
| --- | --- | --- |
| `signIn` | Authentication required | Prompts user to log in |
| `setup` | Missing required configuration | Opens plugin settings dialog |
| `unavailable` | Track cannot be played | Shows notification and skips track |
| `unsupported` | Action not supported | Gracefully suppresses feature |

---

## Resource Limits

| Scope | Quota |
| --- | --- |
| Invocation Timeout | 30s (60s for `stream`, 10 min for `signIn`) |
| Memory Quota | 128 MB |
| Connection Timeout | 15s (60s response read timeout) |
| Max Redirects | 10 |
| Max Response Body | 32 MB |
| Concurrent Timers | 1,000 |
| Concurrent Processes | 16 |

---

## Debugging

- Inspect plugin stdout/stderr in your terminal by launching YesPlayMusic directly:
  - **macOS**: `/Applications/YesPlayMusic.app/Contents/MacOS/YesPlayMusic`
  - **Windows**: Run `YesPlayMusic.exe` from PowerShell
  - **Linux**: Run `yesplaymusic` from shell
- Click **Reload** in Settings → Plugins to reload code changes instantly.
- Load-time errors (malformed manifest, syntax errors, missing requirements) are reported directly on the plugin card in Settings.
