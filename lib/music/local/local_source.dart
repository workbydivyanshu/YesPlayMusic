// 本地音乐源：扫描用户选的文件夹，读取标签、封面和 .lrc 歌词。
//
// ID 约定（只在本源内有意义）：
//   歌曲  = 文件绝对路径
//   专辑  = 'al:' + 专辑艺人 + '\x01' + 专辑名（都做了大小写折叠）
//   艺人  = 'ar:' + 艺人名（折叠）

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart' as tags;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import '../lrc.dart';
import '../models.dart';
import '../source.dart';
import 'mp3_info.dart';

/// 本地源能播放的扩展名 → Stream.type。
const audioTypes = {
  '.mp3': 'mp3',
  '.flac': 'flac',
  '.m4a': 'm4a',
  '.mp4': 'm4a',
  '.aac': 'aac',
  '.ogg': 'ogg',
  '.opus': 'opus',
  '.wav': 'wav',
  '.aif': 'aiff',
  '.aiff': 'aiff',
  '.aifc': 'aiff',
  '.ape': 'ape',
};

/// 文件夹里会被当作专辑封面的图片（不区分大小写）。
const _coverNames = ['cover', 'folder', 'front', 'album', 'albumart'];
const _coverExts = ['.jpg', '.jpeg', '.png', '.webp'];

/// 搜索、分组用的折叠：小写、去首尾空白、合并空白。
String fold(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

/// 扫描结果里的一首歌。只含基本类型，可以跨 isolate 传递。
class LocalEntry {
  LocalEntry({
    required this.path,
    required this.title,
    required this.artists,
    required this.album,
    required this.albumArtist,
    required this.year,
    required this.disc,
    required this.number,
    required this.durationMs,
    required this.cover,
    required this.modified,
  });

  final String path, title, album, cover;

  /// 标签里没写时，扫描结束后由 [_fillAlbumArtists] 补上。
  String albumArtist;
  final List<String> artists;
  final int year, disc, number, durationMs;
  final DateTime modified;
}

class LocalSource extends Source {
  /// [folders]：要扫描的文件夹；[cacheDir]：存放从标签里提取出的封面。
  LocalSource({required this.folders, required this.cacheDir});

  final List<String> folders;
  final String cacheDir;

  @override
  SourceInfo get info => SourceInfo(
    id: 'local',
    name: L.sourceLocal,
    navigation: [NavItem(builtin: 'home', title: L.sourceLocal, icon: 'note')],
  );

  @override
  final Set<String> ops = const {
    Op.home,
    Op.search,
    Op.library,
    Op.album,
    Op.artist,
    Op.lyrics,
    Op.stream,
  };

  List<LocalEntry> _entries = const [];
  Map<String, LocalEntry> _byPath = const {};
  Map<String, List<LocalEntry>> _byAlbum = const {};
  Map<String, List<LocalEntry>> _byArtist = const {};
  Map<String, List<LocalEntry>> _byAlbumArtist = const {};

  /// 专辑加进来的时间：里面最新的那个文件的修改时间。
  Map<String, String> _albumAdded = const {};

  List<LocalEntry> get entries => _entries;
  int get trackCount => _entries.length;

  /// 一个文件夹多久没有进展就放弃扫描。列目录、读文件都是同步的，
  /// 遇到卡住的网络盘（比如 WebDAV）会一直阻塞。
  static const stallTimeout = Duration(seconds: 30);

  final _cancel = Completer<void>();

  /// 上一次 [scan] 因为读不了或卡住而跳过的文件夹。
  List<String> unreadable = const [];

  /// 停止正在进行的 [scan]：它会抛 [ScanCancelled]，索引保持原样。
  void cancelScan() {
    if (!_cancel.isCompleted) _cancel.complete();
  }

  /// 重新扫描所有文件夹。读标签是同步 IO，所以每个文件夹都在自己的后台
  /// isolate 里跑。失败或 [stall] 内没有进展的文件夹会被跳过并记入
  /// [unreadable]，其余仍会进入索引。[onProgress] 收到已读取的文件数。
  Future<void> scan({
    void Function(int files)? onProgress,
    Duration stall = stallTimeout,
  }) async {
    final folders = {for (final f in this.folders) p.normalize(f)};
    var done = 0;
    final results = await Future.wait([
      for (final folder in folders)
        _scanFolder(folder, cacheDir, stall, _cancel.future, () {
          onProgress?.call(++done);
        }),
    ]);
    if (_cancel.isCompleted) throw ScanCancelled();
    final failed = <String>[];
    final seen = <String>{};
    final list = <LocalEntry>[];
    for (final (i, folder) in folders.indexed) {
      final r = results[i];
      if (r == null) {
        failed.add(folder);
        continue;
      }
      for (final e in r) {
        if (seen.add(e.path)) list.add(e);
      }
    }
    _fillAlbumArtists(list);
    unreadable = failed;
    _index(list);
  }

  void _index(List<LocalEntry> list) {
    _entries = list;
    _byPath = {for (final e in list) e.path: e};
    final byAlbum = <String, List<LocalEntry>>{};
    final byArtist = <String, List<LocalEntry>>{};
    final byAlbumArtist = <String, List<LocalEntry>>{};
    for (final e in list) {
      if (e.album.isNotEmpty) {
        (byAlbum[albumId(e)] ??= []).add(e);
        if (e.albumArtist.isNotEmpty) {
          (byAlbumArtist[artistId(e.albumArtist)] ??= []).add(e);
        }
      }
      for (final a in e.artists) {
        (byArtist[artistId(a)] ??= []).add(e);
      }
    }
    for (final ts in byAlbum.values) {
      ts.sort((a, b) {
        final c = a.disc.compareTo(b.disc);
        if (c != 0) return c;
        final n = a.number.compareTo(b.number);
        return n != 0 ? n : a.path.compareTo(b.path);
      });
    }
    _byAlbum = byAlbum;
    _byArtist = byArtist;
    _byAlbumArtist = byAlbumArtist;
    _albumAdded = {
      for (final MapEntry(:key, :value) in byAlbum.entries)
        key: value
            .map((e) => e.modified)
            .reduce((a, b) => a.isAfter(b) ? a : b)
            .toIso8601String(),
    };
  }

  static String albumId(LocalEntry e) =>
      'al:${fold(e.albumArtist)}\x01${fold(e.album)}';
  static String artistId(String name) => 'ar:${fold(name)}';

  String _uri(String path) => path.isEmpty ? '' : Uri.file(path).toString();

  String _albumCover(LocalEntry e) {
    if (e.cover.isNotEmpty) return e.cover;
    for (final track in _byAlbum[albumId(e)] ?? const <LocalEntry>[]) {
      if (track.cover.isNotEmpty) return track.cover;
    }
    return '';
  }

  Album _album(LocalEntry e, {bool withAlbumCover = false}) => e.album.isEmpty
      ? const Album(id: '', name: '')
      : Album(
          id: albumId(e),
          name: e.album,
          imageUrl: _uri(withAlbumCover ? _albumCover(e) : e.cover),
          artists: e.albumArtist.isEmpty
              ? const []
              : [Artist(id: artistId(e.albumArtist), name: e.albumArtist)],
          released: e.year > 0 ? '${e.year}' : '',
          added: _albumAdded[albumId(e)] ?? '',
        );

  Track track(LocalEntry e) => Track(
    id: e.path,
    source: id,
    name: e.title,
    artists: [for (final a in e.artists) Artist(id: artistId(a), name: a)],
    album: _album(e),
    duration: e.durationMs,
    added: e.modified.toIso8601String(),
  );

  List<Album> _albums(Iterable<LocalEntry> es) {
    final seen = <String>{};
    return [
      for (final e in es)
        if (e.album.isNotEmpty && seen.add(albumId(e)))
          _album(e, withAlbumCover: true),
    ];
  }

  List<Artist> _artists() {
    final names = <String, String>{};
    for (final e in _entries) {
      for (final a in e.artists) {
        names.putIfAbsent(artistId(a), () => a);
      }
    }
    final list = [
      for (final m in names.entries) Artist(id: m.key, name: m.value),
    ];
    list.sort((a, b) => fold(a.name).compareTo(fold(b.name)));
    return list;
  }

  @override
  Future<Browse> home() async {
    final recent = List.of(_entries)
      ..sort((a, b) => b.modified.compareTo(a.modified));
    final albums = _albums(_entries)
      ..sort((a, b) => fold(a.name).compareTo(fold(b.name)));
    return Browse(
      title: L.sourceLocal,
      subtitle: L.countSongs(trackCount),
      sections: [
        Section(
          title: L.localRecentlyAdded,
          tracks: [for (final e in recent.take(30)) track(e)],
          empty: L.localEmptyHint,
        ),
        Section(title: L.tabAlbums, albums: albums),
        Section(title: L.tabArtists, artists: _artists()),
      ],
    );
  }

  static const pageSize = 50;

  @override
  Future<SearchResult> search(
    String query,
    SearchKind kind, {
    int offset = 0,
  }) async {
    final q = fold(query);
    if (q.isEmpty) return const SearchResult();
    bool hit(String s) => fold(s).contains(q);

    List<T> page<T>(List<T> all) => all.skip(offset).take(pageSize).toList();
    bool more(int n) => offset + pageSize < n;

    switch (kind) {
      case SearchKind.tracks:
        final all = [
          for (final e in _entries)
            if (hit(e.title) || e.artists.any(hit) || hit(e.album)) e,
        ];
        return SearchResult(
          tracks: page(all).map(track).toList(),
          more: more(all.length),
          total: all.length,
        );
      case SearchKind.albums:
        final all = _albums(
          _entries.where((e) => hit(e.album) || hit(e.albumArtist)),
        );
        return SearchResult(
          albums: page(all),
          more: more(all.length),
          total: all.length,
        );
      case SearchKind.artists:
        final all = _artists().where((a) => hit(a.name)).toList();
        return SearchResult(
          artists: page(all),
          more: more(all.length),
          total: all.length,
        );
      case SearchKind.playlists:
      case SearchKind.shows:
        return const SearchResult();
    }
  }

  /// 本地的整个曲库一次给完。
  @override
  Future<SearchResult> library(SearchKind kind, {int offset = 0}) async {
    if (offset > 0) return const SearchResult();
    return switch (kind) {
      SearchKind.tracks => SearchResult(tracks: _entries.map(track).toList()),
      SearchKind.albums => SearchResult(albums: _albums(_entries)),
      SearchKind.artists => SearchResult(artists: _artists()),
      _ => const SearchResult(),
    };
  }

  @override
  Future<AlbumPage> album(String id) async {
    final es = _byAlbum[id];
    if (es == null) throw SourceError(SourceErrorKind.failed, L.albumNotFound);
    return AlbumPage(
      album: _album(es.first, withAlbumCover: true),
      tracks: es.map(track).toList(),
    );
  }

  @override
  Future<ArtistPage> artist(String id) async {
    final es = _byArtist[id] ?? const [];
    final albumEs = _byAlbumArtist[id] ?? const [];
    if (es.isEmpty && albumEs.isEmpty) {
      throw SourceError(SourceErrorKind.failed, L.localArtistNotFound);
    }
    final name = es.isNotEmpty
        ? es.first.artists.firstWhere((a) => artistId(a) == id)
        : albumEs.first.albumArtist;
    final albums = _albums([...es, ...albumEs])
      ..sort((a, b) => b.released.compareTo(a.released));
    return ArtistPage(
      artist: Artist(id: id, name: name),
      tracks: es.map(track).toList(),
      albums: albums,
    );
  }

  @override
  Future<AudioStream> stream(String id, {String quality = 'high'}) async {
    final e = _byPath[id];
    if (e == null || !File(id).existsSync()) {
      throw SourceError(SourceErrorKind.unavailable, L.localFileMovedOrDeleted);
    }
    return AudioStream(
      url: Uri.file(id).toString(),
      type: audioTypes[p.extension(id).toLowerCase()] ?? '',
      quality: 'lossless',
      size: File(id).lengthSync(),
    );
  }

  /// 先找同名 .lrc（以及 .trans.lrc 翻译），没有再读标签里内嵌的歌词。
  @override
  Future<Lyrics> lyrics(String id) => Isolate.run(() {
    final base = p.withoutExtension(id);
    final lrc = _readSidecar(base, '.lrc');
    if (lrc != null) {
      return Lyrics(
        lrc: lrc,
        translation: _readSidecar(base, '.trans.lrc') ?? '',
      );
    }
    final String embedded;
    try {
      embedded = tags.readMetadata(File(id)).lyrics ?? '';
    } catch (_) {
      return const Lyrics();
    }
    // 内嵌的可能只是纯文本（没有时间戳），这时当作没有逐行歌词。
    if (parseLrc(embedded).isEmpty) return const Lyrics();
    return Lyrics(lrc: embedded);
  });

  /// 同名歌词文件：先精确匹配，再把目录里以文件名开头、扩展名只差大小写的
  /// 文件按小写优先找出来，这样在区分大小写的文件系统上也能读到 .LRC。
  static String? _readSidecar(String base, String extension) {
    final exactPath = '$base$extension';
    final exact = _readText(exactPath);
    if (exact != null) return exact;

    final stem = p.basename(base);
    try {
      for (final entry in Directory(
        p.dirname(base),
      ).listSync(followLinks: false)) {
        final name = p.basename(entry.path);
        if (name == '$stem$extension' || !name.startsWith(stem)) continue;
        if (name.substring(stem.length).toLowerCase() != extension) continue;
        final text = _readText(entry.path);
        if (text != null) return text;
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  static String? _readText(String path) {
    final f = File(path);
    try {
      return f.existsSync() ? f.readAsStringSync() : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null; // 非 UTF-8（比如 GBK）的 LRC，暂不支持
    }
  }
}

// ───────────── 扫描（在后台 isolate 里跑） ─────────────

/// [LocalSource.scan] 在 [LocalSource.cancelScan] 之后抛出。
class ScanCancelled implements Exception {}

/// worker → 主 isolate：扫描完成的文件夹。
class _Done {
  const _Done(this.entries);
  final List<LocalEntry> entries;
}

/// 在自己的 isolate 里扫描一个文件夹。失败或 [stall] 内没有进展时返回 null；
/// 这时会杀掉 isolate，因为阻塞在 IO 上的调用没法用别的方式打断。
Future<List<LocalEntry>?> _scanFolder(
  String folder,
  String cacheDir,
  Duration stall,
  Future<void> cancel,
  void Function() onFile,
) async {
  final port = ReceivePort();
  final result = Completer<List<LocalEntry>?>();
  Isolate? iso;
  Timer? watchdog;
  void finish(List<LocalEntry>? r) {
    if (result.isCompleted) return;
    watchdog?.cancel();
    port.close();
    iso?.kill(priority: Isolate.immediate);
    result.complete(r);
  }

  void arm() {
    watchdog?.cancel();
    watchdog = Timer(stall, () => finish(null));
  }

  unawaited(cancel.then((_) => finish(null)));
  arm();
  port.listen((msg) {
    switch (msg) {
      case _Done(:final entries):
        finish(entries);
      case 1:
        onFile();
        arm();
      case 0:
        arm();
      default:
        finish(null); // 未捕获的错误（[message, stack] 列表）或没有结果就退出（null）
    }
  });
  try {
    iso = await Isolate.spawn(
      _folderWorker,
      (port.sendPort, folder, cacheDir),
      onError: port.sendPort,
      onExit: port.sendPort,
    );
    if (result.isCompleted) iso.kill(priority: Isolate.immediate);
  } catch (_) {
    finish(null);
  }
  return result.future;
}

/// 在 worker isolate 里运行。每列一个目录发 0，每读一个文件发 1
/// （两者都会重置看门狗），最后用 [_Done] 带上所有识别到的音频文件。读不出
/// 标签的文件也收录，用文件名兜底。
void _folderWorker((SendPort, String, String) args) {
  final (out, folder, cacheDir) = args;
  final root = Directory(folder);
  // 文件夹不存在（比如没插上的移动硬盘或默认目录不存在）就当空的。
  if (!root.existsSync()) return out.send(const _Done([]));
  final files = <File>[];
  _walk(root, files, () => out.send(0), isRoot: true);
  files.sort((a, b) => a.path.compareTo(b.path));
  final folderCovers = <String, String>{};
  final tagCovers = <String, String>{}; // 专辑键 → 已提取的封面
  final entries = <LocalEntry>[];
  for (final f in files) {
    final path = p.normalize(f.absolute.path);
    entries.add(_entry(f, path, cacheDir, folderCovers, tagCovers));
    out.send(1);
  }
  out.send(_Done(entries));
}

/// 收集 [dir] 下的音频文件。读不了的子文件夹跳过；根目录读不了则抛出。
void _walk(
  Directory dir,
  List<File> out,
  void Function() onDir, {
  bool isRoot = false,
}) {
  final List<FileSystemEntity> items;
  try {
    items = dir.listSync(followLinks: false);
  } on FileSystemException {
    if (isRoot) rethrow;
    return;
  }
  onDir();
  for (final e in items) {
    if (e is Directory) {
      _walk(e, out, onDir);
    } else if (e is File &&
        audioTypes.containsKey(p.extension(e.path).toLowerCase()) &&
        // macOS 资源分叉文件
        !p.basename(e.path).startsWith('._')) {
      out.add(e);
    }
  }
}

final _discFolder = RegExp(r'^(?:cd|disc|disk)\s*(\d+)$', caseSensitive: false);

/// [dir] 所属的专辑文件夹，以及从 CD1、Disc 2 这类分碟子文件夹名里解析出的碟号。
({String folder, int? disc}) _albumLocation(String dir) {
  final number = _discFolder.firstMatch(p.basename(dir))?.group(1);
  return number == null
      ? (folder: dir, disc: null)
      : (folder: p.dirname(dir), disc: int.tryParse(number));
}

/// 同一张专辑所在的文件夹。CD1、Disc 2 这类分碟子文件夹算作上一级，
/// 这样多碟专辑不会被拆开。
String albumDir(String path) => _albumLocation(p.dirname(path)).folder;

/// 标签里缺专辑艺人时，先继承同文件夹 + 同专辑名里唯一明确的专辑艺人标签，
/// 这样部分标注的专辑不会被拆开；否则取未标注曲目里出现最多的艺人，让合辑保持完整。
void _fillAlbumArtists(List<LocalEntry> entries) {
  final groups = <(String, String), List<LocalEntry>>{};
  for (final e in entries) {
    if (e.album.isEmpty) continue;
    (groups[(albumDir(e.path), fold(e.album))] ??= []).add(e);
  }
  for (final g in groups.values) {
    final tagged = <String, String>{};
    final untagged = <LocalEntry>[];
    final counts = <String, int>{};
    for (final e in g) {
      if (e.albumArtist.isNotEmpty) {
        tagged.putIfAbsent(fold(e.albumArtist), () => e.albumArtist);
      } else {
        untagged.add(e);
        if (e.artists.isNotEmpty) {
          counts[e.artists.first] = (counts[e.artists.first] ?? 0) + 1;
        }
      }
    }
    final artist = tagged.length == 1
        ? tagged.values.single
        : counts.isEmpty
        ? ''
        : counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    for (final e in untagged) {
      e.albumArtist = artist;
    }
  }
}

tags.AudioMetadata _readScanMetadata(File file) {
  // 通用的 MP3 映射会把 TPE2 当作曲目艺人。用格式专用的元数据把 TPE1 和 TPE2 分开。
  final mp3 = p.extension(file.path).toLowerCase() == '.mp3'
      ? tags.readAllMetadata(file, getImage: true)
      : null;
  if (mp3 is tags.Mp3Metadata) {
    return tags.AudioMetadata(
        file: file,
        title: mp3.songName,
        artist: _clean(mp3.leadPerformer) ?? mp3.originalArtist,
        album: mp3.album,
        albumArtist: mp3.bandOrOrchestra,
        year: DateTime(mp3.originalReleaseYear ?? mp3.year ?? 0),
        discNumber: mp3.discNumber,
        trackNumber: mp3.trackNumber,
        duration: mp3.duration,
      )
      ..pictures = mp3.pictures
      ..performers.addAll(mp3.customMetadata['GUEST ARTIST']?.split('/') ?? []);
  }
  return tags.readMetadata(file, getImage: true);
}

LocalEntry _entry(
  File f,
  String path,
  String cacheDir,
  Map<String, String> folderCovers,
  Map<String, String> tagCovers,
) {
  tags.AudioMetadata? m;
  try {
    m = _readScanMetadata(f);
  } catch (_) {
    m = null;
  }

  final (fileArtist, fileTitle) = _fromFilename(
    p.basenameWithoutExtension(path),
  );
  final title = _clean(m?.title) ?? fileTitle;
  var artists = splitArtists(_clean(m?.artist) ?? '');
  if (artists.isEmpty && m != null) {
    artists = [for (final s in m.performers) ...splitArtists(s)];
  }
  if (artists.isEmpty && fileArtist.isNotEmpty) artists = [fileArtist];
  final album = _clean(m?.album) ?? '';
  final albumArtist = _clean(m?.albumArtist) ?? '';

  final isMp3 = p.extension(path).toLowerCase() == '.mp3';
  final duration = (isMp3 ? infoHeaderDuration(f) : null) ?? m?.duration;

  final dir = p.dirname(path);
  final (folder: albumFolder, disc: folderDisc) = _albumLocation(dir);
  String coverIn(String folder) =>
      folderCovers.putIfAbsent(folder, () => _folderCover(folder));
  var cover = coverIn(dir);
  // 唱片子文件夹（CD1、Disc 2 等）自己没有封面时，退回专辑文件夹的封面。
  if (cover.isEmpty && albumFolder != dir) cover = coverIn(albumFolder);
  if (cover.isEmpty && m != null && m.pictures.isNotEmpty) {
    // 专辑艺人此时可能还没确定，按文件夹 + 专辑名去重。
    final key = album.isEmpty ? path : '$albumFolder\x01${fold(album)}';
    cover = tagCovers[key] ??= _saveCover(m.pictures, key, cacheDir);
  }

  return LocalEntry(
    path: path,
    title: title,
    artists: artists,
    album: album,
    albumArtist: album.isEmpty ? '' : albumArtist,
    year: m?.year?.year ?? 0,
    disc: m?.discNumber ?? folderDisc ?? 0,
    number: m?.trackNumber ?? 0,
    durationMs: duration?.inMilliseconds ?? 0,
    cover: cover,
    modified: f.statSync().modified,
  );
}

String? _clean(String? s) {
  final t = s?.replaceAll('\x00', '').trim();
  return t == null || t.isEmpty ? null : t;
}

/// 没有标签时从文件名猜："01. 艺人 - 歌名" → (艺人, 歌名)。
(String, String) _fromFilename(String name) {
  final n = name.replaceFirst(RegExp(r'^\d{1,3}[\s.\-_]+'), '');
  final i = n.indexOf(' - ');
  if (i <= 0) return ('', n.trim());
  return (n.substring(0, i).trim(), n.substring(i + 3).trim());
}

/// 拆分多位艺人。只按明确的分隔符拆，不拆 "&"、"and"（太多乐队名里有）。
List<String> splitArtists(String s) => [
  for (final part in s.split(RegExp(r'\s*(?:;|/|、|\x00)\s*')))
    if (part.trim().isNotEmpty) part.trim(),
];

String _folderCover(String dir) {
  try {
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final ext = p.extension(f.path).toLowerCase();
      final base = p.basenameWithoutExtension(f.path).toLowerCase();
      if (_coverExts.contains(ext) && _coverNames.contains(base)) return f.path;
    }
  } on FileSystemException {
    // 没权限之类，当作没有封面
  }
  return '';
}

/// 把标签里的封面写到缓存目录，同一张专辑只写一次。优先用"封面"类型的图。
String _saveCover(List<tags.Picture> pics, String key, String cacheDir) {
  final pic = pics.firstWhere(
    (x) => x.pictureType == tags.PictureType.coverFront,
    orElse: () => pics.first,
  );
  final ext = switch (pic.mimetype.toLowerCase()) {
    'image/png' => '.png',
    'image/webp' => '.webp',
    _ => '.jpg',
  };
  final digest = sha256.convert(pic.bytes);
  final file = File(p.join(cacheDir, 'covers', '${fnv1a(key)}-$digest$ext'));
  try {
    if (!file.existsSync() || file.lengthSync() != pic.bytes.length) {
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(pic.bytes, flush: true);
    }
    return file.path;
  } on FileSystemException {
    return '';
  }
}

/// 64 位 FNV-1a，用来给缓存文件起稳定的名字。
String fnv1a(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h ^= c;
    h *= 0x100000001b3; // 按 64 位回绕
  }
  // Dart 的 int 是有符号的，分成高低 32 位输出，避免出现负号。
  String hex(int v) => v.toRadixString(16).padLeft(8, '0');
  return hex((h >>> 32) & 0xFFFFFFFF) + hex(h & 0xFFFFFFFF);
}
