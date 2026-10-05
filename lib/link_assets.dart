import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

const kModelMimeType = 'model/gltf-binary';
const kGltfJsonMimeType = 'model/gltf+json';
const kHdrMimeType = 'image/vnd.radiance';
const kZipMimeType = 'application/zip';

/// Art einer eingebetteten Datei, wie sie die KI und der Server kennen.
String assetKind(String mimeType) {
  if (mimeType == kModelMimeType || mimeType == kGltfJsonMimeType) return 'model';
  if (mimeType == kHdrMimeType) return 'environment';
  if (mimeType.startsWith('audio/')) return 'sound';
  return 'texture';
}

/// Datei, die die App aus einem Link übernommen hat.
class LinkFile {
  const LinkFile({
    required this.url,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    required this.info,
  });

  final String url;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  /// Beschreibung für die KI, z. B. die Bauteile eines 3D-Modells.
  final String info;
}

class LinkFetchResult {
  const LinkFetchResult({this.files = const [], this.credit, this.skipped = const [], this.archive});

  final List<LinkFile> files;

  /// Urheberangabe der Seite (z. B. „Ferrari 458 Italia model by …“).
  final String? credit;

  /// Gefundene, aber nicht übernommene Dateien mit Grund.
  final List<String> skipped;

  /// ZIP-Paket (z. B. von Kenney) – der Nutzer wählt daraus aus.
  final LinkArchive? archive;
}

class LinkAssetException implements Exception {
  const LinkAssetException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Auswählbare Datei in einem ZIP-Paket.
class ArchiveItem {
  const ArchiveItem({
    required this.path,
    required this.mimeType,
    required this.size,
    this.previewPath,
  });

  final String path;
  final String mimeType;
  final int size;

  /// Vorschaubild im Paket (z. B. Kenney: Side/raceCarRed.png).
  final String? previewPath;

  String get fileName => path.split('/').last;
  String get kind => assetKind(mimeType);
}

/// Geöffnetes ZIP-Paket mit den Dateien, die sich ins Spiel übernehmen lassen.
class LinkArchive {
  LinkArchive._(this.url, this.fileName, this._archive, this.items, this.license);

  final String url;
  final String fileName;
  final Archive _archive;
  final List<ArchiveItem> items;

  /// Lizenz aus der beiliegenden License.txt (z. B. „Creative Commons Zero, CC0“).
  final String? license;

  static const maxItems = 600;
  static final _hidden = RegExp(r'(^|/)(__MACOSX|\.)');
  static final _previewFile = RegExp(r'^(preview|sample|thumbnail)\.(png|jpe?g|webp)$');

  /// Öffnet ein ZIP und bietet Modelle, HDR, Sounds und Bilder zur Auswahl an.
  /// Vorschaubilder von Modellen werden zugeordnet statt einzeln angeboten.
  static LinkArchive open(Uint8List bytes, {required String url, required String fileName}) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const LinkAssetException('Das ZIP-Paket ist beschädigt.');
    }

    final files = [
      for (final file in archive.files)
        if (file.isFile && !_hidden.hasMatch(file.name)) file,
    ];
    String base(String path) =>
        path.split('/').last.replaceFirst(RegExp(r'\.[^.]*$'), '').toLowerCase();

    final models = {
      for (final file in files)
        if (_mimeFromName(file.name) case final mime? when assetKind(mime) == 'model') base(file.name),
    };
    final previews = <String, String>{};
    final items = <ArchiveItem>[];
    for (final file in files) {
      final mime = _mimeFromName(file.name);
      if (mime == null) continue;
      if (assetKind(mime) == 'texture' && models.isNotEmpty) {
        final name = base(file.name);
        final model = models.where((m) => name == m || name.startsWith('${m}_')).firstOrNull;
        // Bilder neben Modellen sind meist Vorschauen: zuordnen statt anbieten.
        if (model != null) {
          final isSide = file.name.toLowerCase().contains('side');
          if (!previews.containsKey(model) || isSide) previews[model] = file.name;
          continue;
        }
        if (_previewFile.hasMatch(file.name.split('/').last.toLowerCase())) continue;
      }
      items.add(ArchiveItem(path: file.name, mimeType: mime, size: file.size));
    }

    const order = ['model', 'environment', 'sound', 'texture'];
    items.sort((a, b) {
      final kind = order.indexOf(a.kind).compareTo(order.indexOf(b.kind));
      return kind != 0 ? kind : a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    if (items.isEmpty) {
      throw const LinkAssetException(
        'Im ZIP-Paket sind keine 3D-Modelle, HDR-Dateien, Sounds oder Bilder.',
      );
    }

    return LinkArchive._(
      url,
      fileName,
      archive,
      [
        for (final item in items.take(maxItems))
          item.kind == 'model' && previews[base(item.path)] != null
              ? ArchiveItem(
                  path: item.path,
                  mimeType: item.mimeType,
                  size: item.size,
                  previewPath: previews[base(item.path)],
                )
              : item,
      ],
      _license(files),
    );
  }

  static String? _license(List<ArchiveFile> files) {
    final file = files.where((f) => RegExp(r'(^|/)licen[cs]e[^/]*\.txt$', caseSensitive: false).hasMatch(f.name)).firstOrNull;
    if (file == null) return null;
    final text = utf8.decode(file.readBytes() ?? const [], allowMalformed: true);
    final line = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => RegExp(r'cc0|creative commons|public domain|licen[cs]e', caseSensitive: false).hasMatch(l))
        .firstOrNull;
    if (line == null || line.isEmpty) return null;
    return line.length > 200 ? '${line.substring(0, 197)}…' : line;
  }

  static String? _mimeFromName(String path) {
    final ext = path.toLowerCase().split('.').last;
    return switch (ext) {
      'glb' => kModelMimeType,
      'gltf' => kGltfJsonMimeType,
      'hdr' => kHdrMimeType,
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'ogg' => 'audio/ogg',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      _ => null,
    };
  }

  Uint8List? read(String path) => _archive.find(path)?.readBytes();

  /// Vorschau für die Auswahlliste: zugeordnetes Bild oder das Bild selbst.
  Uint8List? preview(ArchiveItem item) {
    if (item.previewPath != null) return read(item.previewPath!);
    return item.kind == 'texture' ? read(item.path) : null;
  }

  /// Packt die gewählten Dateien aus. glTF-Dateien bekommen ihre Buffer und
  /// Texturen eingebettet, damit sie als eine Datei im Spiel liegen.
  List<LinkFile> extract(Iterable<ArchiveItem> selected) => [
        for (final item in selected) _extract(item),
      ];

  LinkFile _extract(ArchiveItem item) {
    var bytes = read(item.path);
    if (bytes == null) throw LinkAssetException('${item.fileName}: nicht lesbar');
    String info;
    if (item.mimeType == kGltfJsonMimeType) {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) throw LinkAssetException('${item.fileName}: kein glTF');
      _embedResources(json, item.path);
      bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      info = LinkAssetFetcher.describeGltf(json);
    } else {
      info = LinkAssetFetcher.describe(item.mimeType, bytes, item.fileName);
    }
    return LinkFile(
      url: '$url#${item.path}',
      fileName: item.fileName,
      mimeType: item.mimeType,
      bytes: bytes,
      info: license == null ? info : '$info; Lizenz: $license',
    );
  }

  void _embedResources(Map<String, dynamic> json, String gltfPath) {
    final dir = gltfPath.contains('/') ? gltfPath.substring(0, gltfPath.lastIndexOf('/') + 1) : '';
    for (final key in ['buffers', 'images']) {
      for (final entry in json[key] as List? ?? const []) {
        if (entry is! Map || entry['uri'] is! String) continue;
        final uri = entry['uri'] as String;
        if (uri.startsWith('data:')) continue;
        final path = _resolve(dir, Uri.decodeComponent(uri));
        final data = read(path);
        if (data == null) {
          throw LinkAssetException('${gltfPath.split('/').last}: $uri fehlt im Paket');
        }
        final mime = key == 'buffers'
            ? 'application/octet-stream'
            : LinkAssetFetcher.detectMimeType(data) ?? 'image/png';
        entry['uri'] = 'data:$mime;base64,${base64Encode(data)}';
      }
    }
  }

  static String _resolve(String dir, String relative) {
    final parts = <String>[];
    for (final part in '$dir$relative'.split('/')) {
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (part.isNotEmpty && part != '.') {
        parts.add(part);
      }
    }
    return parts.join('/');
  }
}

/// Lädt 3D-Modelle (.glb), HDR-Umgebungen, Sounds und Texturen aus einem Link:
/// direkt verlinkte Dateien, ZIP-Pakete (z. B. von Kenney) oder alle Dateien,
/// die eine Seite (z. B. ein Beispiel auf threejs.org) lädt. Die KI selbst kann
/// nichts herunterladen – das macht die App.
class LinkAssetFetcher {
  LinkAssetFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const maxFiles = 6;
  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxArchiveBytes = 60 * 1024 * 1024;
  static const maxTotalBytes = 20 * 1024 * 1024;
  static const _maxPageBytes = 3 * 1024 * 1024;
  static const _timeout = Duration(seconds: 90);

  static final _fileRef = RegExp(
    r'''["'`]([^"'`\s<>]+?\.(?:glb|hdr|png|jpe?g|webp|ogg|mp3|wav|zip))(?:\?[^"'`\s<>]*)?["'`]''',
    caseSensitive: false,
  );
  static final _gltfRef = RegExp(r'''["'`]([^"'`\s<>]+?\.gltf)["'`]''', caseSensitive: false);
  static final _infoDiv = RegExp(
    r'''<div[^>]*id\s*=\s*["']info["'][^>]*>([\s\S]*?)</div>''',
    caseSensitive: false,
  );
  static final _directFile = RegExp(r'\.(glb|hdr|png|jpe?g|webp|ogg|mp3|wav|zip)$', caseSensitive: false);
  static final _shadowTexture = RegExp(r'(^|[_-])(ao|shadow)([_.-]|$)', caseSensitive: false);

  /// Bilder auf normalen Webseiten sind meist Logos und Symbole – übernommen
  /// werden nur Bilder aus typischen Textur- und Modellordnern.
  static final _textureFolder = RegExp(r'/(textures?|models?|sprites?|maps?)/', caseSensitive: false);

  void close() => _client.close();

  /// Macht aus Beispiel-Links die Adresse der eigentlichen Seite bzw. Datei:
  /// threejs.org/examples/#name → threejs.org/examples/name.html und
  /// github.com/…/blob/… → raw.githubusercontent.com/….
  static Uri normalize(Uri uri) {
    if (uri.host.endsWith('threejs.org') &&
        uri.path.endsWith('/examples/') &&
        uri.fragment.isNotEmpty) {
      return Uri(scheme: 'https', host: uri.host, path: '${uri.path}${uri.fragment}.html');
    }
    final segments = uri.pathSegments;
    if (uri.host == 'github.com' && segments.length > 4 && segments[2] == 'blob') {
      return Uri.https(
        'raw.githubusercontent.com',
        [segments[0], segments[1], ...segments.sublist(3)].join('/'),
      );
    }
    return uri.removeFragment();
  }

  Future<LinkFetchResult> fetch(String link) async {
    final uri = normalize(Uri.parse(link.trim()));
    if (_directFile.hasMatch(uri.path)) return _fetchFile(uri);

    final html = utf8.decode(await _get(uri, _maxPageBytes), allowMalformed: true);
    final models = <Uri>[], environments = <Uri>[], sounds = <Uri>[], textures = <Uri>[];
    final archives = <Uri>[];
    final skippedShadows = <String>[];
    for (final match in _fileRef.allMatches(html)) {
      final ref = match.group(1)!;
      if (ref.startsWith('data:')) continue;
      final url = uri.resolve(ref);
      if (url.scheme != 'https' && url.scheme != 'http') continue;
      final path = url.path.toLowerCase();
      // Schattenbilder (z. B. ferrari_ao.png) setzte die KI im Test als
      // leuchtende oder riesige dunkle Fläche ein – die Spiele werfen ohnehin
      // echte Schatten.
      if (_shadowTexture.hasMatch(_fileName(url)) && !path.endsWith('.zip')) {
        final note = '${_fileName(url)}: Schattenbild – das Spiel erzeugt eigene Schatten';
        if (!skippedShadows.contains(note)) skippedShadows.add(note);
        continue;
      }
      final bucket = switch (path.split('.').last) {
        'glb' => models,
        'hdr' => environments,
        'ogg' || 'mp3' || 'wav' => sounds,
        'zip' => archives,
        _ => _textureFolder.hasMatch(path) ? textures : null,
      };
      if (bucket != null && !bucket.contains(url)) bucket.add(url);
    }

    // Seiten mit Download-Paket (z. B. Kenney): das Paket zur Auswahl öffnen.
    if (models.isEmpty && environments.isEmpty && archives.isNotEmpty) {
      final result = await _fetchFile(archives.first);
      return LinkFetchResult(archive: result.archive, files: result.files, credit: extractCredit(html));
    }

    final skipped = [
      ...skippedShadows,
      for (final match in _gltfRef.allMatches(html))
        '${_fileName(uri.resolve(match.group(1)!))}: .gltf bitte als ZIP-Paket übernehmen',
    ];
    final files = <LinkFile>[];
    var total = 0;
    for (final url in [...models, ...environments, ...sounds, ...textures]) {
      if (files.length >= maxFiles) {
        skipped.add('${_fileName(url)}: höchstens $maxFiles Dateien pro Link');
        continue;
      }
      try {
        final file = await _download(url, maxFileBytes);
        if (total + file.bytes.length > maxTotalBytes) {
          skipped.add('${file.fileName}: zusammen größer als ${maxTotalBytes ~/ (1024 * 1024)} MB');
          continue;
        }
        total += file.bytes.length;
        files.add(file);
      } on LinkAssetException catch (e) {
        skipped.add('${_fileName(url)}: ${e.message}');
      }
    }

    if (files.isEmpty) {
      throw LinkAssetException(
        skipped.isEmpty
            ? 'Auf der Seite wurden keine 3D-Modelle, HDR-Dateien, Sounds, Texturen oder Download-Pakete gefunden.'
            : 'Keine Datei ließ sich übernehmen – ${skipped.first}',
      );
    }
    return LinkFetchResult(files: files, credit: extractCredit(html), skipped: skipped);
  }

  /// Einzelne Datei oder ZIP-Paket von einer direkten Adresse.
  Future<LinkFetchResult> _fetchFile(Uri url) async {
    // Download-Adressen verraten das Format nicht immer (z. B. …/get?file=x.zip).
    final bytes = await _get(url, maxArchiveBytes);
    if (detectMimeType(bytes) == kZipMimeType) {
      return LinkFetchResult(archive: LinkArchive.open(bytes, url: url.toString(), fileName: _fileName(url)));
    }
    if (bytes.length > maxFileBytes) throw LinkAssetException(_tooLarge(maxFileBytes));
    return LinkFetchResult(files: [_toFile(url, bytes)]);
  }

  /// Lädt eine Datei, die schon im Browser angetippt wurde (Download-Knopf).
  Future<LinkFetchResult> fetchDownload(String url) => _fetchFile(normalize(Uri.parse(url)));

  Future<LinkFile> _download(Uri url, int limit) async => _toFile(url, await _get(url, limit));

  LinkFile _toFile(Uri url, Uint8List bytes) {
    final mimeType = detectMimeType(bytes);
    if (mimeType == null || mimeType == kZipMimeType) {
      throw const LinkAssetException('unbekanntes Dateiformat');
    }
    return LinkFile(
      url: url.toString(),
      fileName: _fileName(url),
      mimeType: mimeType,
      bytes: bytes,
      info: describe(mimeType, bytes, _fileName(url)),
    );
  }

  /// Beschreibung einer Datei für die KI.
  static String describe(String mimeType, Uint8List bytes, String fileName) {
    if (mimeType == kModelMimeType) return describeGlb(bytes);
    if (mimeType == kHdrMimeType) return 'Umgebungslicht (HDR-Panorama)';
    if (mimeType.startsWith('audio/')) return 'Sounddatei (${mimeType.split('/').last.toUpperCase()})';
    final name = fileName.toLowerCase();
    if (RegExp(r'normal').hasMatch(name)) return 'Normal Map (Oberflächenrelief)';
    if (RegExp(r'rough').hasMatch(name)) return 'Roughness Map (Rauheit)';
    if (RegExp(r'metal').hasMatch(name)) return 'Metalness Map';
    if (RegExp(r'color|albedo|diffuse|basecolor').hasMatch(name)) return 'Farbtextur';
    return 'Bild (Sprite oder Textur)';
  }

  /// Lädt höchstens [limit] Bytes; größere Dateien werden abgelehnt.
  Future<Uint8List> _get(Uri url, int limit) async {
    try {
      final response = await _client.send(http.Request('GET', url)).timeout(_timeout);
      if (response.statusCode != 200) {
        throw LinkAssetException('nicht erreichbar (HTTP ${response.statusCode})');
      }
      final length = response.contentLength;
      if (length != null && length > limit) throw LinkAssetException(_tooLarge(limit));
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(_timeout)) {
        builder.add(chunk);
        if (builder.length > limit) throw LinkAssetException(_tooLarge(limit));
      }
      return builder.takeBytes();
    } on TimeoutException {
      throw const LinkAssetException('Zeitüberschreitung beim Laden');
    } on http.ClientException catch (e) {
      throw LinkAssetException('Netzwerkfehler: ${e.message}');
    }
  }

  static String _tooLarge(int limit) => 'größer als ${limit ~/ (1024 * 1024)} MB';

  static String _fileName(Uri url) =>
      url.pathSegments.isEmpty ? url.host : Uri.decodeComponent(url.pathSegments.last);

  /// Erkennt GLB, HDR, Bilder, Sounds und ZIP anhand der ersten Bytes.
  static String? detectMimeType(List<int> bytes) {
    bool startsWith(List<int> prefix, [int offset = 0]) {
      if (bytes.length < offset + prefix.length) return false;
      for (var i = 0; i < prefix.length; i++) {
        if (bytes[offset + i] != prefix[i]) return false;
      }
      return true;
    }

    if (startsWith(ascii.encode('glTF'))) return kModelMimeType;
    if (startsWith(ascii.encode('#?RADIANCE')) || startsWith(ascii.encode('#?RGBE'))) {
      return kHdrMimeType;
    }
    if (startsWith([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (startsWith([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith(ascii.encode('RIFF')) && startsWith(ascii.encode('WEBP'), 8)) {
      return 'image/webp';
    }
    if (startsWith(ascii.encode('RIFF')) && startsWith(ascii.encode('WAVE'), 8)) {
      return 'audio/wav';
    }
    if (startsWith(ascii.encode('OggS'))) return 'audio/ogg';
    if (startsWith(ascii.encode('ID3')) ||
        (bytes.length > 1 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0)) {
      return 'audio/mpeg';
    }
    if (startsWith([0x50, 0x4B, 0x03, 0x04])) return kZipMimeType;
    return null;
  }

  /// Fasst ein GLB-Modell für die KI zusammen: benannte Teile, Materialien
  /// und Animationen – damit sie z. B. Räder drehen oder den Lack umfärben kann.
  static String describeGlb(Uint8List bytes) {
    try {
      final data = ByteData.sublistView(bytes);
      final jsonLength = data.getUint32(12, Endian.little);
      final json = jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)));
      return json is Map<String, dynamic> ? describeGltf(json) : '3D-Modell (glTF)';
    } catch (_) {
      return '3D-Modell (glTF)';
    }
  }

  static String describeGltf(Map<String, dynamic> json) {
    List<String> names(String key, int max) => <String>{
          for (final entry in json[key] as List? ?? const [])
            if (entry is Map && entry['name'] is String && (entry['name'] as String).isNotEmpty)
              entry['name'] as String,
        }.take(max).toList();

    final nodes = names('nodes', 60);
    final materials = names('materials', 30);
    final animations = names('animations', 20);
    final bounds = describeBounds(json);
    return [
      '3D-Modell (glTF)',
      if (bounds != null) bounds,
      if (nodes.isNotEmpty) 'benannte Teile: ${nodes.join(', ')}',
      if (materials.isNotEmpty) 'Materialien: ${materials.join(', ')}',
      if (animations.isNotEmpty) 'Animationen: ${animations.join(', ')}',
    ].join('; ');
  }

  /// Maße des Modells in der Szene (inkl. Verschiebung, Drehung und Skalierung
  /// der Knoten) – damit die KI Modelle passend skaliert und Bausatz-Teile wie
  /// Straßenstücke lückenlos aneinandersetzt.
  static String? describeBounds(Map<String, dynamic> json) {
    try {
      final accessors = json['accessors'] as List? ?? const [];
      final meshes = json['meshes'] as List? ?? const [];
      final allNodes = json['nodes'] as List? ?? const [];
      final scenes = json['scenes'] as List? ?? const [];
      final sceneIndex = (json['scene'] as num?)?.toInt() ?? 0;
      final roots = scenes.isEmpty
          ? List.generate(allNodes.length, (i) => i)
          : [for (final n in (scenes[sceneIndex] as Map)['nodes'] as List? ?? const []) (n as num).toInt()];

      final min = [double.infinity, double.infinity, double.infinity];
      final max = [double.negativeInfinity, double.negativeInfinity, double.negativeInfinity];

      void visit(int index, List<double> parent, int depth) {
        if (depth > 64 || index >= allNodes.length) return;
        final node = allNodes[index] as Map;
        final world = _multiply(parent, _localMatrix(node));
        final mesh = node['mesh'];
        if (mesh is num && mesh < meshes.length) {
          for (final primitive in (meshes[mesh.toInt()] as Map)['primitives'] as List? ?? const []) {
            final position = ((primitive as Map)['attributes'] as Map?)?['POSITION'];
            if (position is! num) continue;
            final accessor = accessors[position.toInt()] as Map;
            final lo = [for (final v in accessor['min'] as List) (v as num).toDouble()];
            final hi = [for (final v in accessor['max'] as List) (v as num).toDouble()];
            for (var corner = 0; corner < 8; corner++) {
              final p = _transform(world, [
                corner & 1 == 0 ? lo[0] : hi[0],
                corner & 2 == 0 ? lo[1] : hi[1],
                corner & 4 == 0 ? lo[2] : hi[2],
              ]);
              for (var axis = 0; axis < 3; axis++) {
                if (p[axis] < min[axis]) min[axis] = p[axis];
                if (p[axis] > max[axis]) max[axis] = p[axis];
              }
            }
          }
        }
        for (final child in node['children'] as List? ?? const []) {
          visit((child as num).toInt(), world, depth + 1);
        }
      }

      for (final root in roots) {
        visit(root, _identity, 0);
      }
      if (min[0] == double.infinity) return null;
      String f(double v) => v.toStringAsFixed(2);
      return 'Maße ca. ${f(max[0] - min[0])} × ${f(max[1] - min[1])} × ${f(max[2] - min[2])} '
          '(x × y × z, y = oben), von x ${f(min[0])} bis ${f(max[0])}, '
          'y ${f(min[1])} bis ${f(max[1])}, z ${f(min[2])} bis ${f(max[2])}';
    } catch (_) {
      return null;
    }
  }

  static const _identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

  /// Lokale Matrix eines glTF-Knotens (spaltenweise wie im glTF-Standard).
  static List<double> _localMatrix(Map node) {
    final matrix = node['matrix'];
    if (matrix is List && matrix.length == 16) {
      return [for (final v in matrix) (v as num).toDouble()];
    }
    List<double> vec(String key, List<double> fallback) =>
        node[key] is List ? [for (final v in node[key] as List) (v as num).toDouble()] : fallback;
    final t = vec('translation', [0, 0, 0]);
    final q = vec('rotation', [0, 0, 0, 1]);
    final s = vec('scale', [1, 1, 1]);
    final (x, y, z, w) = (q[0], q[1], q[2], q[3]);
    return [
      (1 - 2 * (y * y + z * z)) * s[0], (2 * (x * y + z * w)) * s[0], (2 * (x * z - y * w)) * s[0], 0,
      (2 * (x * y - z * w)) * s[1], (1 - 2 * (x * x + z * z)) * s[1], (2 * (y * z + x * w)) * s[1], 0,
      (2 * (x * z + y * w)) * s[2], (2 * (y * z - x * w)) * s[2], (1 - 2 * (x * x + y * y)) * s[2], 0,
      t[0], t[1], t[2], 1,
    ];
  }

  static List<double> _multiply(List<double> a, List<double> b) => [
        for (var col = 0; col < 4; col++)
          for (var row = 0; row < 4; row++)
            a[row] * b[col * 4] + a[4 + row] * b[col * 4 + 1] + a[8 + row] * b[col * 4 + 2] + a[12 + row] * b[col * 4 + 3],
      ];

  static List<double> _transform(List<double> m, List<double> p) => [
        for (var row = 0; row < 3; row++) m[row] * p[0] + m[4 + row] * p[1] + m[8 + row] * p[2] + m[12 + row],
      ];

  /// Urheberangabe aus dem Infobereich einer Seite (wie bei threejs.org). Nur
  /// die Zeilen mit Urheber oder Lizenz – den Titel des Beispiels nicht, sonst
  /// versucht Gemini, das Beispiel wörtlich nachzuschreiben, und bricht ab.
  static String? extractCredit(String html) {
    final match = _infoDiv.firstMatch(html);
    if (match == null) return null;
    final lines = [
      for (final line in match.group(1)!.split(RegExp(r'<br\s*/?>|\n', caseSensitive: false)))
        line
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll('&nbsp;', ' ')
            .replaceAll('&amp;', '&')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
    ].where(_attribution.hasMatch);
    final text = lines.join(' · ');
    if (text.isEmpty) return null;
    return text.length > 300 ? '${text.substring(0, 297)}…' : text;
  }

  static final _attribution = RegExp(
    r'\b(by|von|author|autor|license|lizenz|cc[ -]?by|cc0)\b|©|\(c\)',
    caseSensitive: false,
  );
}
