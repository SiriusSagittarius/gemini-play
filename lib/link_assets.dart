import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
  const LinkFetchResult({required this.files, this.credit, this.skipped = const []});

  final List<LinkFile> files;

  /// Urheberangabe der Seite (z. B. „Ferrari 458 Italia model by …“).
  final String? credit;

  /// Gefundene, aber nicht übernommene Dateien mit Grund.
  final List<String> skipped;
}

class LinkAssetException implements Exception {
  const LinkAssetException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lädt 3D-Modelle (.glb), HDR-Umgebungen und Texturen aus einem Link: direkt
/// verlinkte Dateien oder alle Dateien, die eine Seite (z. B. ein Beispiel auf
/// threejs.org) lädt. Die KI selbst kann nichts herunterladen – das macht die App.
class LinkAssetFetcher {
  LinkAssetFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const maxFiles = 6;
  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxTotalBytes = 20 * 1024 * 1024;
  static const _maxPageBytes = 3 * 1024 * 1024;
  static const _timeout = Duration(seconds: 60);

  static final _fileRef = RegExp(
    r'''["'`]([^"'`\s<>]+?\.(?:glb|hdr|png|jpe?g|webp))(?:\?[^"'`\s<>]*)?["'`]''',
    caseSensitive: false,
  );
  static final _gltfRef = RegExp(r'''["'`]([^"'`\s<>]+?\.gltf)["'`]''', caseSensitive: false);
  static final _infoDiv = RegExp(
    r'''<div[^>]*id\s*=\s*["']info["'][^>]*>([\s\S]*?)</div>''',
    caseSensitive: false,
  );
  static final _modelOrHdr = RegExp(r'\.(glb|hdr)$', caseSensitive: false);
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
    if (_modelOrHdr.hasMatch(uri.path) || _isImagePath(uri.path)) {
      return LinkFetchResult(files: [await _download(uri)]);
    }

    final html = utf8.decode(await _get(uri, _maxPageBytes), allowMalformed: true);
    final models = <Uri>[], environments = <Uri>[], textures = <Uri>[];
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
      if (_shadowTexture.hasMatch(_fileName(url))) {
        final note = '${_fileName(url)}: Schattenbild – das Spiel erzeugt eigene Schatten';
        if (!skippedShadows.contains(note)) skippedShadows.add(note);
        continue;
      }
      final bucket = path.endsWith('.glb')
          ? models
          : path.endsWith('.hdr')
              ? environments
              : _textureFolder.hasMatch(path)
                  ? textures
                  : null;
      if (bucket != null && !bucket.contains(url)) bucket.add(url);
    }

    final skipped = [
      ...skippedShadows,
      for (final match in _gltfRef.allMatches(html))
        '${_fileName(uri.resolve(match.group(1)!))}: .gltf wird nicht unterstützt, nur .glb',
    ];
    final files = <LinkFile>[];
    var total = 0;
    for (final url in [...models, ...environments, ...textures]) {
      if (files.length >= maxFiles) {
        skipped.add('${_fileName(url)}: höchstens $maxFiles Dateien pro Link');
        continue;
      }
      try {
        final file = await _download(url);
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
            ? 'Auf der Seite wurden keine 3D-Modelle (.glb), HDR-Dateien oder Texturen gefunden.'
            : 'Keine Datei ließ sich übernehmen – ${skipped.first}',
      );
    }
    return LinkFetchResult(files: files, credit: extractCredit(html), skipped: skipped);
  }

  Future<LinkFile> _download(Uri url) async {
    final bytes = await _get(url, maxFileBytes);
    final mimeType = detectMimeType(bytes);
    if (mimeType == null) {
      throw const LinkAssetException('unbekanntes Dateiformat');
    }
    return LinkFile(
      url: url.toString(),
      fileName: _fileName(url),
      mimeType: mimeType,
      bytes: bytes,
      info: switch (mimeType) {
        'model/gltf-binary' => describeGlb(bytes),
        'image/vnd.radiance' => 'Umgebungslicht (HDR-Panorama)',
        _ => 'Bild bzw. Textur',
      },
    );
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

  static bool _isImagePath(String path) =>
      RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(path);

  static String _fileName(Uri url) =>
      url.pathSegments.isEmpty ? url.host : Uri.decodeComponent(url.pathSegments.last);

  /// Erkennt GLB, HDR, PNG, JPEG und WebP anhand der ersten Bytes.
  static String? detectMimeType(List<int> bytes) {
    bool startsWith(List<int> prefix, [int offset = 0]) {
      if (bytes.length < offset + prefix.length) return false;
      for (var i = 0; i < prefix.length; i++) {
        if (bytes[offset + i] != prefix[i]) return false;
      }
      return true;
    }

    if (startsWith(ascii.encode('glTF'))) return 'model/gltf-binary';
    if (startsWith(ascii.encode('#?RADIANCE')) || startsWith(ascii.encode('#?RGBE'))) {
      return 'image/vnd.radiance';
    }
    if (startsWith([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (startsWith([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith(ascii.encode('RIFF')) && startsWith(ascii.encode('WEBP'), 8)) {
      return 'image/webp';
    }
    return null;
  }

  /// Fasst ein GLB-Modell für die KI zusammen: benannte Teile, Materialien
  /// und Animationen – damit sie z. B. Räder drehen oder den Lack umfärben kann.
  static String describeGlb(Uint8List bytes) {
    const fallback = '3D-Modell (glTF)';
    try {
      final data = ByteData.sublistView(bytes);
      final jsonLength = data.getUint32(12, Endian.little);
      final json = jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)));
      if (json is! Map<String, dynamic>) return fallback;

      List<String> names(String key, int max) => <String>{
            for (final entry in json[key] as List? ?? const [])
              if (entry is Map && entry['name'] is String && (entry['name'] as String).isNotEmpty)
                entry['name'] as String,
          }.take(max).toList();

      final nodes = names('nodes', 60);
      final materials = names('materials', 30);
      final animations = names('animations', 20);
      return [
        fallback,
        if (nodes.isNotEmpty) 'benannte Teile: ${nodes.join(', ')}',
        if (materials.isNotEmpty) 'Materialien: ${materials.join(', ')}',
        if (animations.isNotEmpty) 'Animationen: ${animations.join(', ')}',
      ].join('; ');
    } catch (_) {
      return fallback;
    }
  }

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
