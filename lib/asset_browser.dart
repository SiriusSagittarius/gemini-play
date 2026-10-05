import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'link_assets.dart';

/// Vorgeschlagene Quelle im Asset-Browser.
class AssetSource {
  const AssetSource({
    required this.name,
    required this.url,
    required this.description,
    required this.license,
    required this.icon,
    this.freeToUse = true,
  });

  final String name;
  final String url;
  final String description;
  final String license;
  final IconData icon;

  /// CC0: auch in geteilten und veröffentlichten Spielen ohne Nennung nutzbar.
  final bool freeToUse;
}

const kAssetSources = [
  AssetSource(
    name: 'Kenney – 3D-Modelle',
    url: 'https://kenney.nl/assets/category:3D',
    description: 'Rennautos, Strecken, Figuren, Städte, Weltraum – als Paket mit Vorschau',
    license: 'CC0 – frei, auch kommerziell',
    icon: Icons.view_in_ar,
  ),
  AssetSource(
    name: 'Kenney – Sounds',
    url: 'https://kenney.nl/assets/category:Audio',
    description: 'Soundeffekte und Musik für Spiele',
    license: 'CC0 – frei, auch kommerziell',
    icon: Icons.music_note,
  ),
  AssetSource(
    name: 'Kenney – 2D-Grafiken',
    url: 'https://kenney.nl/assets/category:2D',
    description: 'Figuren, Kacheln und Oberflächen für 2D-Spiele',
    license: 'CC0 – frei, auch kommerziell',
    icon: Icons.image_outlined,
  ),
  AssetSource(
    name: 'Poly Haven',
    url: 'https://polyhaven.com/hdris',
    description: 'HDR-Himmel für echtes Licht und Spiegelungen',
    license: 'CC0 – frei, auch kommerziell',
    icon: Icons.wb_twilight,
  ),
  AssetSource(
    name: 'ambientCG',
    url: 'https://ambientcg.com/list?type=Material&sort=Popular',
    description: 'Texturen wie Asphalt, Gras, Holz oder Metall',
    license: 'CC0 – frei, auch kommerziell',
    icon: Icons.texture,
  ),
  AssetSource(
    name: 'three.js-Beispiele',
    url: 'https://threejs.org/examples/',
    description: 'Beispiel öffnen und „Diese Seite übernehmen“ – holt Modelle und Licht',
    license: 'Modelle von verschiedenen Urhebern – Lizenz prüfen',
    icon: Icons.code,
    freeToUse: false,
  ),
  AssetSource(
    name: 'Khronos glTF-Beispiele',
    url: 'https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models',
    description: 'Referenzmodelle; im Ordner „glTF-Binary“ die .glb-Datei öffnen',
    license: 'je Modell, meist CC BY oder CC0',
    icon: Icons.category_outlined,
    freeToUse: false,
  ),
];

/// Was der Nutzer im Asset-Browser gesammelt hat.
class AssetBrowserResult {
  const AssetBrowserResult({
    this.files = const [],
    this.references = const [],
    this.pages = const [],
  });

  /// Dateien fürs Spiel (Modelle, Sounds, Bilder, HDR).
  final List<LinkFile> files;

  /// Bilder, die die KI nur ansieht.
  final List<LinkFile> references;

  /// Übernommene Seiten – Gemini kann sie zusätzlich als Vorlage lesen.
  final List<String> pages;

  bool get isEmpty => files.isEmpty && references.isEmpty;
}

/// Hängt die Urheberangabe einer Seite an die Beschreibung jeder Datei.
List<LinkFile> withCredit(List<LinkFile> files, String? credit) => [
      for (final file in files)
        credit == null
            ? file
            : LinkFile(
                url: file.url,
                fileName: file.fileName,
                mimeType: file.mimeType,
                bytes: file.bytes,
                info: '${file.info}; Herkunft: $credit',
              ),
    ];

/// Verkleinert ein Bild, bis es als Referenz an die KI passt (≤ [maxBytes]).
Future<LinkFile> shrinkForAi(LinkFile image, {int maxBytes = 650000}) async {
  if (image.bytes.length <= maxBytes) return image;
  for (final width in [1024, 768, 512, 384]) {
    final codec = await ui.instantiateImageCodec(image.bytes, targetWidth: width);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data != null && data.lengthInBytes <= maxBytes) {
      return LinkFile(
        url: image.url,
        fileName: image.fileName,
        mimeType: 'image/png',
        bytes: data.buffer.asUint8List(),
        info: image.info,
      );
    }
  }
  throw const LinkAssetException('Das Bild ist zu groß.');
}

/// Durchsuchen von Quellen und Übernehmen von Dateien in die App – die KI
/// selbst kann nichts herunterladen.
class AssetBrowserScreen extends StatefulWidget {
  const AssetBrowserScreen({super.key, required this.maxFiles, required this.maxReferences});

  final int maxFiles;
  final int maxReferences;

  @override
  State<AssetBrowserScreen> createState() => _AssetBrowserScreenState();
}

class _AssetBrowserScreenState extends State<AssetBrowserScreen> {
  final _fetcher = LinkAssetFetcher();
  final _files = <LinkFile>[];
  final _references = <LinkFile>[];
  final _pages = <String>[];
  InAppWebViewController? _controller;
  AssetSource? _source;
  String? _url;
  String _title = '';
  bool _canGoBack = false;
  bool _busy = false;

  @override
  void dispose() {
    _fetcher.close();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _finish() => Navigator.of(context).pop(
        AssetBrowserResult(files: _files, references: _references, pages: _pages),
      );

  Future<void> _back() async {
    if (_canGoBack && _controller != null) {
      await _controller!.goBack();
    } else {
      setState(() {
        _source = null;
        _url = null;
      });
    }
  }

  /// Übernimmt eine Seite (Beispiele, Pakete) oder einen Download.
  Future<void> _import(String url, {bool download = false}) async {
    if (_busy) return;
    if (url.startsWith('blob:')) {
      _message('Diese Seite erzeugt die Datei selbst – bitte einen direkten Download-Link nutzen.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = download ? await _fetcher.fetchDownload(url) : await _fetcher.fetch(url);
      if (!mounted) return;
      var files = withCredit(result.files, result.credit);
      final archive = result.archive;
      if (archive != null) {
        final picked = await showArchivePicker(
          context,
          archive,
          maxCount: widget.maxFiles - _files.length,
        );
        if (picked == null || picked.isEmpty || !mounted) return;
        files = withCredit(archive.extract(picked), result.credit);
      }
      _addFiles(files);
      if (!download && result.archive == null && !_pages.contains(url)) _pages.add(url);
      if (result.skipped.isNotEmpty) {
        _message('${files.length} übernommen, ${result.skipped.length} übersprungen: ${result.skipped.first}');
      }
    } on LinkAssetException catch (e) {
      _message(e.message);
    } catch (e) {
      _message('Übernehmen fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addFiles(List<LinkFile> files) {
    final room = widget.maxFiles - _files.length;
    final added = [
      for (final file in files)
        if (!_files.any((f) => f.url == file.url)) file,
    ].take(room).toList();
    setState(() => _files.addAll(added));
    if (added.isNotEmpty) {
      _message('${added.length} Datei(en) übernommen – insgesamt ${_files.length}.');
    } else if (room <= 0) {
      _message('Mehr Dateien passen nicht in ein Spiel.');
    }
  }

  /// Langer Druck auf ein Bild: ins Spiel übernehmen oder nur als Referenz.
  Future<void> _onLongPress(InAppWebViewHitTestResult hit) async {
    final controller = _controller;
    if (controller == null) return;
    if (hit.type != InAppWebViewHitTestResultType.IMAGE_TYPE &&
        hit.type != InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE) {
      return;
    }
    final url = (await controller.requestImageRef())?.url?.toString() ?? hit.extra;
    if (url == null || !mounted) return;

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Nur als Referenz'),
              subtitle: const Text(
                'Die KI schaut sich das Bild an und gestaltet eigene Grafiken in dem Stil – '
                'das Bild selbst kommt nicht ins Spiel. Auch für geschützte Bilder.',
              ),
              onTap: () => Navigator.of(sheetContext).pop('reference'),
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('Ins Spiel übernehmen'),
              subtitle: const Text('Nur wenn du das Bild nutzen darfst, z. B. CC0.'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final file = url.startsWith('data:image/')
          ? _fromDataUrl(url)
          : (await _fetcher.fetchDownload(url)).files.firstOrNull;
      if (file == null || !file.mimeType.startsWith('image/') || file.mimeType == kHdrMimeType) {
        throw const LinkAssetException('Das ist kein Bild, das sich übernehmen lässt.');
      }
      if (choice == 'file') {
        _addFiles([file]);
      } else if (_references.length >= widget.maxReferences) {
        _message('Höchstens ${widget.maxReferences} Referenzbilder pro Spiel.');
      } else {
        final small = await shrinkForAi(file);
        setState(() => _references.add(small));
        _message('Als Referenz gemerkt – insgesamt ${_references.length}.');
      }
    } on LinkAssetException catch (e) {
      _message(e.message);
    } catch (e) {
      _message('Bild konnte nicht übernommen werden: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  LinkFile _fromDataUrl(String url) {
    final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
    final mime = LinkAssetFetcher.detectMimeType(bytes);
    if (mime == null) throw const LinkAssetException('Unbekanntes Bildformat.');
    return LinkFile(url: 'data:', fileName: 'bild', mimeType: mime, bytes: bytes, info: 'Bild');
  }

  @override
  Widget build(BuildContext context) {
    final count = _files.length + _references.length;
    return PopScope<Object?>(
      canPop: _url == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _url == null ? 'Quellen' : (_title.isEmpty ? _source?.name ?? '' : _title),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_url != null)
              IconButton(
                tooltip: 'Quellen',
                icon: const Icon(Icons.home_outlined),
                onPressed: () => setState(() {
                  _source = null;
                  _url = null;
                }),
              ),
            TextButton.icon(
              onPressed: _finish,
              icon: Badge(
                isLabelVisible: count > 0,
                label: Text('$count'),
                child: const Icon(Icons.check),
              ),
              label: const Text('Fertig'),
            ),
          ],
        ),
        body: _url == null ? _buildSources(context) : _buildBrowser(context),
      ),
    );
  }

  Widget _buildSources(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          'Öffne eine Quelle und tippe dort auf „Download“ oder unten auf „Diese Seite '
          'übernehmen“. Bei Paketen wählst du aus, was ins Spiel soll. Lange auf ein '
          'beliebiges Bild drücken: „Nur als Referenz“ – die KI orientiert sich daran, '
          'ohne es zu kopieren.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        for (final source in kAssetSources)
          Card(
            child: ListTile(
              leading: Icon(source.icon, color: theme.colorScheme.primary),
              title: Text(source.name),
              subtitle: Text('${source.description}\n${source.license}'),
              isThreeLine: true,
              trailing: source.freeToUse
                  ? Chip(
                      label: const Text('CC0'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.secondaryContainer,
                    )
                  : null,
              onTap: () => setState(() {
                _source = source;
                _url = source.url;
                _title = '';
                _canGoBack = false;
              }),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'CC0 heißt: frei nutzbar, auch in geteilten Spielen, ohne Namensnennung. Bei '
          'anderen Quellen gilt die Lizenz des jeweiligen Urhebers. Marken wie Automarken '
          'oder bekannte Figuren sind zusätzlich geschützt.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildBrowser(BuildContext context) {
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: InAppWebView(
            key: ValueKey(_url),
            initialUrlRequest: URLRequest(url: WebUri(_url!)),
            initialSettings: InAppWebViewSettings(
              useOnDownloadStart: true,
              mediaPlaybackRequiresUserGesture: true,
              supportZoom: true,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            onTitleChanged: (_, title) => setState(() => _title = title ?? ''),
            onLoadStop: (controller, _) async {
              final canGoBack = await controller.canGoBack();
              if (mounted) setState(() => _canGoBack = canGoBack);
            },
            onDownloadStartRequest: (_, request) => _import(request.url.toString(), download: true),
            onLongPressHitTestResult: (_, hit) => _onLongPress(hit),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Zurück',
                  onPressed: _busy ? null : _back,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final url = (await _controller?.getUrl())?.toString();
                            if (url != null) await _import(url);
                          },
                    icon: const Icon(Icons.download),
                    label: const Text('Diese Seite übernehmen'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Auswahl aus einem ZIP-Paket mit Vorschaubildern, Suche und Größenanzeige.
Future<List<ArchiveItem>?> showArchivePicker(
  BuildContext context,
  LinkArchive archive, {
  required int maxCount,
}) =>
    Navigator.of(context).push<List<ArchiveItem>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ArchivePicker(archive: archive, maxCount: maxCount),
      ),
    );

class _ArchivePicker extends StatefulWidget {
  const _ArchivePicker({required this.archive, required this.maxCount});

  final LinkArchive archive;
  final int maxCount;

  @override
  State<_ArchivePicker> createState() => _ArchivePickerState();
}

class _ArchivePickerState extends State<_ArchivePicker> {
  final _selected = <ArchiveItem>{};
  final _previews = <String, Uint8List?>{};
  String _query = '';
  String? _kind;

  static const _kinds = {
    'model': ('3D', Icons.view_in_ar),
    'sound': ('Sounds', Icons.music_note),
    'texture': ('Bilder', Icons.image_outlined),
    'environment': ('HDR', Icons.wb_twilight),
  };

  int get _bytes => _selected.fold(0, (sum, item) => sum + item.size);

  Uint8List? _preview(ArchiveItem item) =>
      _previews.putIfAbsent(item.path, () => widget.archive.preview(item));

  String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';

  void _toggle(ArchiveItem item) {
    setState(() {
      if (_selected.remove(item)) return;
      if (_selected.length >= widget.maxCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Höchstens ${widget.maxCount} Dateien.')),
        );
        return;
      }
      if (_bytes + item.size > LinkAssetFetcher.maxTotalBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zusammen höchstens 20 MB pro Spiel.')),
        );
        return;
      }
      _selected.add(item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = {for (final item in widget.archive.items) item.kind};
    final items = [
      for (final item in widget.archive.items)
        if ((_kind == null || item.kind == _kind) &&
            item.path.toLowerCase().contains(_query.toLowerCase()))
          item,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(widget.archive.fileName, overflow: TextOverflow.ellipsis)),
      body: Column(
        children: [
          if (widget.archive.license != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Lizenz: ${widget.archive.license}', style: theme.textTheme.bodySmall),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Suchen, z. B. car, road, engine …',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text('Alle (${widget.archive.items.length})'),
                    selected: _kind == null,
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                ),
                for (final entry in _kinds.entries)
                  if (available.contains(entry.key))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        avatar: Icon(entry.value.$2, size: 18),
                        label: Text(entry.value.$1),
                        selected: _kind == entry.key,
                        onSelected: (_) => setState(() => _kind = entry.key),
                      ),
                    ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, index) {
                final item = items[index];
                final preview = _preview(item);
                return CheckboxListTile(
                  value: _selected.contains(item),
                  onChanged: (_) => _toggle(item),
                  secondary: SizedBox.square(
                    dimension: 48,
                    child: preview != null
                        ? Image.memory(preview, cacheWidth: 96, fit: BoxFit.contain, gaplessPlayback: true)
                        : Icon(_kinds[item.kind]?.$2 ?? Icons.insert_drive_file_outlined),
                  ),
                  title: Text(item.fileName, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${_kinds[item.kind]?.$1 ?? ''} · ${_size(item.size)}'),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_selected.length} gewählt · ${_size(_bytes)}'),
                  ),
                  FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop([
                              for (final item in widget.archive.items)
                                if (_selected.contains(item)) item,
                            ]),
                    child: const Text('Übernehmen'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
