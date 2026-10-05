import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker;

import 'asset_browser.dart';
import 'link_assets.dart';
import 'main.dart';

// ---------------------------------------------------------------------------
// Projekt-Icon (Liste und Startbildschirm-Verknüpfung)
// ---------------------------------------------------------------------------

/// Gleichbleibende Farbe pro Projekt.
Color projectColor(String seed) {
  const palette = [
    Color(0xFF6750A4),
    Color(0xFF1E88E5),
    Color(0xFF00897B),
    Color(0xFF43A047),
    Color(0xFFF4511E),
    Color(0xFFD81B60),
    Color(0xFF8E24AA),
    Color(0xFF3949AB),
    Color(0xFFFB8C00),
    Color(0xFF00ACC1),
  ];
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

String projectInitial(String title) {
  final letters = title.trim().characters.where((c) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c));
  return letters.isEmpty ? '?' : letters.first.toUpperCase();
}

/// Kleines farbiges Icon mit Anfangsbuchstaben.
class ProjectIcon extends StatelessWidget {
  const ProjectIcon({super.key, required this.project, this.size = 40});

  final AppProject project;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = projectColor(project.id);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.2)!, color],
        ),
      ),
      child: Text(
        projectInitial(project.title),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.48,
        ),
      ),
    );
  }
}

/// Icon als PNG für die Verknüpfung (adaptives Icon: Motiv in der Mitte).
Future<Uint8List> renderProjectIcon(AppProject project) async {
  const size = 432.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final color = projectColor(project.id);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, size, size),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(size, size),
        [Color.lerp(color, Colors.white, 0.25)!, color],
      ),
  );
  final text = TextPainter(
    text: TextSpan(
      text: projectInitial(project.title),
      style: const TextStyle(color: Colors.white, fontSize: 170, fontWeight: FontWeight.w700),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, Offset((size - text.width) / 2, (size - text.height) / 2));
  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

// ---------------------------------------------------------------------------
// Verknüpfungen auf dem Startbildschirm (siehe MainActivity.kt)
// ---------------------------------------------------------------------------

class ProjectShortcuts {
  ProjectShortcuts._();

  static const _channel = MethodChannel('promptplay/shortcuts');

  /// Bittet den Launcher, eine Verknüpfung anzulegen. `false`, wenn er das
  /// nicht unterstützt.
  static Future<bool> pin(AppProject project) async {
    try {
      final icon = await renderProjectIcon(project);
      return await _channel.invokeMethod<bool>('pin', {
            'id': project.id,
            'title': project.title,
            'icon': icon,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('Verknüpfung fehlgeschlagen: $e');
      return false;
    }
  }

  /// Projekt, mit dessen Verknüpfung die App gestartet wurde.
  static Future<String?> initialProject() async {
    try {
      return await _channel.invokeMethod<String>('initialProject');
    } on MissingPluginException {
      return null;
    }
  }

  /// Verknüpfung angetippt, während die App schon läuft.
  static void listen(void Function(String projectId) onOpen) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openProject' && call.arguments is String) {
        onOpen(call.arguments as String);
      }
    });
  }
}

/// Androids Dateiauswahl (siehe MainActivity.kt) – für Sounds, Modelle und Pakete.
class DeviceFiles {
  DeviceFiles._();

  static const _channel = MethodChannel('promptplay/files');

  /// Gewählte Dateien oder `null`, wenn abgebrochen.
  static Future<List<({String name, Uint8List bytes})>?> pick() async {
    try {
      final files = await _channel.invokeListMethod<Map<Object?, Object?>>('pick');
      if (files == null) return null;
      return [
        for (final file in files)
          if (file['name'] is String && file['bytes'] is Uint8List)
            (name: file['name'] as String, bytes: file['bytes'] as Uint8List),
      ];
    } on MissingPluginException {
      return null;
    }
  }

  /// „Speichern unter“-Dialog. `true` = gespeichert, `false` = Fehler,
  /// `null` = abgebrochen.
  static Future<bool?> save(String name, String mimeType, Uint8List bytes) async {
    try {
      return await _channel.invokeMethod<bool>('save', {
        'name': name,
        'mimeType': mimeType,
        'bytes': bytes,
      });
    } on MissingPluginException {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Größe eines Projekts
// ---------------------------------------------------------------------------

typedef ProjectSize = ({int code, int media, int mediaCount, int versions, int versionCount});

Future<ProjectSize> projectSize(AppProject project) async {
  final assets = await AppStore.loadAssets(project.id);
  final versions = await AppStore.loadVersions(project.id);
  return (
    code: utf8.encode(project.htmlCode).length,
    media: assets.fold(0, (sum, asset) => sum + asset.data.length * 3 ~/ 4),
    mediaCount: assets.length,
    versions: versions.fold(0, (sum, version) => sum + utf8.encode(version.htmlCode).length),
    versionCount: versions.length,
  );
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

// ---------------------------------------------------------------------------
// Medien-Ordner eines Projekts
// ---------------------------------------------------------------------------

/// Bilder, Sounds und 3D-Modelle eines Spiels verwalten. Neue Dateien nutzt
/// das Spiel, sobald es weitergebaut wird. Liefert „extend“, wenn der Nutzer
/// direkt weiterbauen möchte.
class ProjectMediaScreen extends StatefulWidget {
  const ProjectMediaScreen({super.key, required this.project});

  final AppProject project;

  @override
  State<ProjectMediaScreen> createState() => _ProjectMediaScreenState();
}

class _ProjectMediaScreenState extends State<ProjectMediaScreen> {
  late AppProject _project = widget.project;
  List<GameImage> _assets = const [];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    AppStore.loadAssets(_project.id).then((assets) {
      if (mounted) {
        setState(() {
          _assets = assets;
          _loading = false;
        });
      }
    });
  }

  void _message(String text) => showMessage(context, text);

  String _uniqueName(String base) {
    final taken = {for (final asset in _assets) asset.name};
    if (!taken.contains(base)) return base;
    for (var i = 2;; i++) {
      final suffix = '_$i';
      final stem = base.length + suffix.length > 30 ? base.substring(0, 30 - suffix.length) : base;
      if (!taken.contains('$stem$suffix')) return '$stem$suffix';
    }
  }

  Future<void> _save(List<GameImage> assets) async {
    final updated = _project.copyWith(assetNames: [for (final asset in assets) asset.name]);
    await AppStore.saveProject(updated, assets: assets);
    if (!mounted) return;
    setState(() {
      _project = updated;
      _assets = assets;
      _changed = true;
    });
  }

  Future<void> _addFiles(List<LinkFile> files) async {
    final room = kMaxAssets - _assets.length;
    final added = <GameImage>[];
    for (final file in files.take(room)) {
      final base = GameImage.sanitizeName(file.fileName.replaceFirst(RegExp(r'\.[^.]*$'), ''));
      final name = _uniqueName(base);
      final asset = GameImage(
        name: name,
        mimeType: file.mimeType,
        data: base64Encode(file.bytes),
        source: file.url,
        info: file.info,
      );
      added.add(asset);
      _assets = [..._assets, asset];
    }
    if (added.isEmpty) {
      _message(room <= 0 ? 'Höchstens $kMaxAssets Dateien pro Spiel.' : 'Nichts übernommen.');
      return;
    }
    await _save(_assets);
    _message('${added.length} Datei(en) im Medien-Ordner.');
  }

  Future<void> _addPhotos() async {
    final own = _assets.where((asset) => asset.isOwnImage).length;
    final remaining = kMaxImages - own;
    if (remaining <= 0) {
      _message('Höchstens $kMaxImages eigene Bilder pro Spiel.');
      return;
    }
    final picked = await ImagePicker().pickMultiImage(
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
      limit: remaining,
    );
    final added = <GameImage>[];
    for (final file in picked.take(remaining)) {
      final bytes = await file.readAsBytes();
      final mimeType = GameImage.detectMimeType(bytes);
      final data = base64Encode(bytes);
      if (mimeType == null || data.length > kMaxImageBase64) continue;
      final base = GameImage.sanitizeName(file.name.replaceFirst(RegExp(r'\.[^.]*$'), ''));
      final asset = GameImage(name: _uniqueName(base), mimeType: mimeType, data: data);
      added.add(asset);
      _assets = [..._assets, asset];
    }
    if (added.isNotEmpty) await _save(_assets);
  }

  /// Sounds, 3D-Modelle (.glb), HDR, Bilder oder ZIP-Pakete vom Gerät.
  Future<void> _addDeviceFiles() async {
    final result = await DeviceFiles.pick();
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    final files = <LinkFile>[];
    final problems = <String>[];
    try {
      for (final picked in result) {
        final bytes = picked.bytes;
        final mime = LinkAssetFetcher.detectMimeType(bytes);
        if (mime == kZipMimeType) {
          final archive = LinkArchive.open(bytes, url: 'gerät:${picked.name}', fileName: picked.name);
          if (!mounted) return;
          final chosen = await showArchivePicker(context, archive, maxCount: kMaxAssets - _assets.length);
          files.addAll(archive.extract(chosen ?? const []));
        } else if (mime == null) {
          problems.add('${picked.name}: unbekanntes Format');
        } else if (bytes.length > LinkAssetFetcher.maxFileBytes) {
          problems.add('${picked.name}: größer als 10 MB');
        } else {
          files.add(LinkFile(
            url: 'gerät:${picked.name}',
            fileName: picked.name,
            mimeType: mime,
            bytes: bytes,
            info: LinkAssetFetcher.describe(mime, bytes, picked.name),
          ));
        }
      }
      if (files.isNotEmpty) await _addFiles(files);
      if (problems.isNotEmpty) _message(problems.join('\n'));
    } on LinkAssetException catch (e) {
      _message(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFromSources() async {
    final result = await Navigator.of(context).push<AssetBrowserResult>(
      MaterialPageRoute(
        builder: (_) => AssetBrowserScreen(maxFiles: kMaxAssets - _assets.length, maxReferences: 0),
      ),
    );
    if (result != null && result.files.isNotEmpty) await _addFiles(result.files);
  }

  Future<void> _remove(GameImage asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('„${asset.name}“ entfernen?'),
        content: const Text(
          'Nutzt das Spiel die Datei schon, fehlt sie danach. Bau das Spiel dann weiter, '
          'z. B. mit „Die Datei … gibt es nicht mehr“.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Entfernen')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _save([
      for (final other in _assets)
        if (other.name != asset.name) other,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Medien · ${_project.title}', overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (_busy) const LinearProgressIndicator(),
                Text(
                  'Hier liegen Bilder, Sounds und 3D-Modelle für dieses Spiel – offline und '
                  'beim Teilen dabei. Neue Dateien nutzt das Spiel, sobald du es '
                  'weiterbaust, z. B. mit „Nutze den Sound engine als Motorgeräusch“.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Fotos'),
                      onPressed: _busy ? null : _addPhotos,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.folder_open),
                      label: const Text('Dateien vom Handy'),
                      onPressed: _busy ? null : _addDeviceFiles,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.travel_explore),
                      label: const Text('Aus Quellen'),
                      onPressed: _busy ? null : _addFromSources,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_assets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Noch keine Dateien.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  )
                else
                  for (final asset in _assets)
                    Card(
                      child: ListTile(
                        leading: _assetIcon(asset),
                        title: Text(asset.name),
                        subtitle: Text(
                          [
                            switch (asset.kind) {
                              'model' => '3D-Modell',
                              'environment' => 'HDR-Licht',
                              'sound' => 'Sound',
                              _ => asset.isOwnImage ? 'Eigenes Bild' : 'Bild/Textur',
                            },
                            formatBytes(asset.data.length * 3 ~/ 4),
                            if (asset.source != null && !asset.source!.startsWith('gerät:'))
                              Uri.tryParse(asset.source!)?.host ?? '',
                          ].where((part) => part.isNotEmpty).join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Entfernen',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy ? null : () => _remove(asset),
                        ),
                      ),
                    ),
                if (_changed) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop('extend'),
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Jetzt weiterbauen'),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _assetIcon(GameImage asset) {
    if (asset.kind == 'texture') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          base64Decode(asset.data),
          width: 48,
          height: 48,
          cacheWidth: 96,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => const Icon(Icons.image_outlined),
        ),
      );
    }
    return SizedBox.square(
      dimension: 48,
      child: Icon(switch (asset.kind) {
        'model' => Icons.view_in_ar,
        'environment' => Icons.wb_twilight,
        _ => Icons.music_note,
      }),
    );
  }
}
