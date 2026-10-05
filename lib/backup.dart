import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'main.dart';
import 'project_tools.dart';

/// Kennung in der Sicherungsdatei, damit fremde ZIPs erkannt werden.
const kBackupFormat = 'promptplay-backup';
const _manifestName = 'promptplay-backup.json';

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef BackupResult = ({int added, int updated, int skipped});

/// Sicherung aller Spiele (Code, Medien, Versionen) als eine ZIP-Datei – damit
/// sie eine Neuinstallation oder einen Handywechsel überstehen.
class ProjectBackup {
  ProjectBackup._();

  static String fileName(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'PromptPlay-Backup-${now.year}-${two(now.month)}-${two(now.day)}.zip';
  }

  static Future<({Uint8List bytes, int projects})> create() async {
    final projects = await AppStore.loadProjects();
    final archive = Archive()
      ..add(ArchiveFile.string(
        _manifestName,
        jsonEncode({
          'format': kBackupFormat,
          'version': 1,
          'createdAt': DateTime.now().toIso8601String(),
          'projects': projects.length,
        }),
      ));
    for (final project in projects) {
      final assets = await AppStore.loadAssets(project.id);
      final versions = await AppStore.loadVersions(project.id);
      final dir = 'projects/${project.id}';
      archive
        ..add(ArchiveFile.string('$dir/project.json', jsonEncode(project.toJson())))
        ..add(ArchiveFile.string('$dir/assets.json', jsonEncode([for (final a in assets) a.toJson()])))
        ..add(ArchiveFile.string('$dir/versions.json', jsonEncode([for (final v in versions) v.toJson()])));
    }
    return (bytes: ZipEncoder().encodeBytes(archive), projects: projects.length);
  }

  /// Spielt eine Sicherung ein. Vorhandene Spiele werden nur ersetzt, wenn die
  /// Sicherung neuer ist.
  static Future<BackupResult> restore(Uint8List bytes) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const BackupException('Das ist keine PromptPlay-Sicherung.');
    }
    final manifest = archive.find(_manifestName)?.readBytes();
    final Object? info;
    try {
      info = manifest == null ? null : jsonDecode(utf8.decode(manifest));
    } catch (_) {
      throw const BackupException('Die Sicherung ist beschädigt.');
    }
    if (info is! Map || info['format'] != kBackupFormat) {
      throw const BackupException('Das ist keine PromptPlay-Sicherung.');
    }

    final existing = {for (final project in await AppStore.loadProjects()) project.id: project};
    var added = 0, updated = 0, skipped = 0;
    for (final file in archive.files) {
      final match = RegExp(r'^projects/([^/]+)/project\.json$').firstMatch(file.name);
      if (match == null) continue;
      try {
        final project = AppProject.fromJson(_json(archive, file.name) as Map<String, dynamic>);
        final old = existing[project.id];
        if (old != null && !project.updatedAt.isAfter(old.updatedAt)) {
          skipped++;
          continue;
        }
        final dir = 'projects/${match.group(1)}';
        final assets = [
          for (final entry in _json(archive, '$dir/assets.json', fallback: const []) as List)
            GameImage.fromJson(entry as Map<String, dynamic>),
        ];
        final versions = [
          for (final entry in _json(archive, '$dir/versions.json', fallback: const []) as List)
            ProjectVersion.fromJson(entry as Map<String, dynamic>),
        ];
        await AppStore.saveProject(project, assets: assets, versions: versions);
        old == null ? added++ : updated++;
      } catch (e) {
        debugPrint('Projekt aus Sicherung nicht lesbar (${file.name}): $e');
        skipped++;
      }
    }
    return (added: added, updated: updated, skipped: skipped);
  }

  static Object? _json(Archive archive, String name, {Object? fallback}) {
    final bytes = archive.find(name)?.readBytes();
    return bytes == null ? fallback : jsonDecode(utf8.decode(bytes));
  }
}

// ---------------------------------------------------------------------------
// Abläufe für die Oberfläche
// ---------------------------------------------------------------------------

Future<T> _withProgress<T>(BuildContext context, String text, Future<T> Function() work) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );
  try {
    return await work();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// „Backup speichern“: Android fragt, wohin (Downloads, Google Drive …).
Future<void> saveBackupFlow(BuildContext context) async {
  try {
    final backup = await _withProgress(context, 'Sicherung wird erstellt …', ProjectBackup.create);
    if (backup.projects == 0) {
      if (context.mounted) showMessage(context, 'Noch keine Spiele zum Sichern.');
      return;
    }
    final saved = await DeviceFiles.save(
      ProjectBackup.fileName(DateTime.now()),
      'application/zip',
      backup.bytes,
    );
    if (!context.mounted || saved == null) return;
    showMessage(
      context,
      saved
          ? '${backup.projects} Spiel(e) gesichert.'
          : 'Speichern fehlgeschlagen – versuch „Backup teilen“.',
    );
  } catch (e) {
    if (context.mounted) showMessage(context, 'Sicherung fehlgeschlagen: $e');
  }
}

/// „Backup teilen“: z. B. an sich selbst schicken oder in Drive ablegen.
Future<void> shareBackupFlow(BuildContext context) async {
  try {
    final backup = await _withProgress(context, 'Sicherung wird erstellt …', ProjectBackup.create);
    if (backup.projects == 0) {
      if (context.mounted) showMessage(context, 'Noch keine Spiele zum Sichern.');
      return;
    }
    final name = ProjectBackup.fileName(DateTime.now());
    await Share.shareXFiles(
      [XFile.fromData(backup.bytes, mimeType: 'application/zip', name: name)],
      subject: 'PromptPlay-Sicherung',
      fileNameOverrides: [name],
    );
  } catch (e) {
    if (context.mounted) showMessage(context, 'Sicherung fehlgeschlagen: $e');
  }
}

/// „Backup einspielen“. Liefert `true`, wenn Spiele dazugekommen sind.
Future<bool> restoreBackupFlow(BuildContext context) async {
  final files = await DeviceFiles.pick();
  if (files == null || files.isEmpty || !context.mounted) return false;
  try {
    final result = await _withProgress(
      context,
      'Sicherung wird eingespielt …',
      () => ProjectBackup.restore(files.first.bytes),
    );
    if (!context.mounted) return false;
    showMessage(
      context,
      [
        if (result.added > 0) '${result.added} Spiel(e) wiederhergestellt',
        if (result.updated > 0) '${result.updated} aktualisiert',
        if (result.skipped > 0) '${result.skipped} schon vorhanden',
      ].join(', ').ifEmpty('Die Sicherung enthält keine Spiele.'),
    );
    return result.added + result.updated > 0;
  } on BackupException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return false;
  } catch (e) {
    if (context.mounted) showMessage(context, 'Einspielen fehlgeschlagen: $e');
    return false;
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
