import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctions, FirebaseFunctionsException, HttpsCallableOptions;
import 'package:crypto/crypto.dart' show sha256;
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart'
    show
        InAppPurchase,
        ProductDetails,
        PurchaseDetails,
        PurchaseParam,
        PurchaseStatus;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final cloud = cloudService = CloudService();
    final store = CreditStore(cloud);
    creditShop = store;
    unawaited(store.start());
  } catch (e) {
    debugPrint('Firebase nicht verfügbar, nur eigene API-Keys möglich: $e');
  }
  runApp(const PromptPlayApp());
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class PromptPlayApp extends StatelessWidget {
  const PromptPlayApp({super.key});

  static const _seedColor = Color(0xFF6750A4);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PromptPlay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seedColor),
      darkTheme: ThemeData(
        colorSchemeSeed: _seedColor,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// KI-Anbieter
// ---------------------------------------------------------------------------

enum AiProvider {
  gemini(
    label: 'Gemini',
    vendor: 'Google AI Studio',
    icon: Icons.auto_awesome,
    description: 'Google Gemini: sehr leistungsfähig, auch bei großen Spielen. '
        'Kostenloser Key über Google AI Studio.',
    keyUrl: 'https://aistudio.google.com/apikey',
    keyPrefix: 'AIza',
    createKeyStep: 'Auf „API-Schlüssel erstellen“ tippen '
        '(falls gefragt, ein Projekt auswählen).',
    defaultModel: 'gemini-flash-latest',
    suggestedModels: [
      'gemini-flash-latest',
      'gemini-3.8-flash',
      'gemini-3.5-flash',
      'gemini-pro-latest',
    ],
  ),
  groq(
    label: 'Groq',
    vendor: 'GroqCloud',
    icon: Icons.bolt,
    description: 'Groq: extrem schnelle Antworten mit offenen Modellen '
        '(z. B. GPT-OSS, Llama) und großzügigem Tageskontingent. '
        'Kostenloser Key über GroqCloud.',
    keyUrl: 'https://console.groq.com/keys',
    keyPrefix: 'gsk_',
    createKeyStep: 'Auf „Create API Key“ tippen und einen beliebigen Namen '
        'vergeben.',
    defaultModel: 'openai/gpt-oss-120b',
    suggestedModels: [
      'openai/gpt-oss-120b',
      'llama-3.3-70b-versatile',
      'openai/gpt-oss-20b',
    ],
  );

  const AiProvider({
    required this.label,
    required this.vendor,
    required this.icon,
    required this.description,
    required this.keyUrl,
    required this.keyPrefix,
    required this.createKeyStep,
    required this.defaultModel,
    required this.suggestedModels,
  });

  final String label;
  final String vendor;
  final IconData icon;
  final String description;
  final String keyUrl;
  final String keyPrefix;
  final String createKeyStep;
  final String defaultModel;
  final List<String> suggestedModels;

  AiService createService() => switch (this) {
        AiProvider.gemini => GeminiService(),
        AiProvider.groq => GroqService(),
      };
}

// ---------------------------------------------------------------------------
// Datenmodell
// ---------------------------------------------------------------------------

class AppProject {
  const AppProject({
    required this.id,
    required this.title,
    required this.prompt,
    required this.htmlCode,
    required this.createdAt,
    this.generatedBy,
  });

  final String id;
  final String title;
  final String prompt;
  final String htmlCode;
  final DateTime createdAt;

  /// Anbieter und Modell, z. B. „Groq · openai/gpt-oss-120b“.
  final String? generatedBy;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'prompt': prompt,
        'htmlCode': htmlCode,
        'createdAt': createdAt.toIso8601String(),
        if (generatedBy != null) 'generatedBy': generatedBy,
      };

  factory AppProject.fromJson(Map<String, dynamic> json) => AppProject(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Ohne Titel',
        prompt: json['prompt'] as String? ?? '',
        htmlCode: json['htmlCode'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        generatedBy: json['generatedBy'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Lokaler Speicher (shared_preferences)
// ---------------------------------------------------------------------------

class AppStore {
  AppStore._();

  static const _providerKey = 'ai_provider';
  static const _projectsKey = 'projects';

  // Ergibt „gemini_api_key“ bzw. „groq_api_key“ (kompatibel zu älteren Versionen).
  static String _apiKeyKey(AiProvider provider) => '${provider.name}_api_key';
  static String _modelKey(AiProvider provider) => '${provider.name}_model';

  static Future<AiProvider> getProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_providerKey);
    return AiProvider.values.firstWhere(
      (provider) => provider.name == name,
      orElse: () => AiProvider.gemini,
    );
  }

  static Future<void> setProvider(AiProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerKey, provider.name);
  }

  static Future<String> getApiKey(AiProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey(provider)) ?? '';
  }

  static Future<void> setApiKey(AiProvider provider, String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey(provider), apiKey.trim());
  }

  static Future<String> getModel(AiProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    final model = prefs.getString(_modelKey(provider))?.trim() ?? '';
    return model.isEmpty ? provider.defaultModel : model;
  }

  static Future<void> setModel(AiProvider provider, String model) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = model.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_modelKey(provider));
    } else {
      await prefs.setString(_modelKey(provider), trimmed);
    }
  }

  /// Lädt alle Projekte, neueste zuerst. Beschädigte Einträge werden übersprungen.
  static Future<List<AppProject>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_projectsKey);
    if (raw == null || raw.isEmpty) return [];

    final projects = <AppProject>[];
    try {
      for (final entry in jsonDecode(raw) as List<dynamic>) {
        try {
          projects.add(AppProject.fromJson(entry as Map<String, dynamic>));
        } catch (e) {
          debugPrint('Projekt übersprungen: $e');
        }
      }
    } catch (e) {
      debugPrint('Projektliste konnte nicht gelesen werden: $e');
    }
    projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return projects;
  }

  static Future<void> saveProjects(List<AppProject> projects) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _projectsKey,
      jsonEncode(projects.map((p) => p.toJson()).toList()),
    );
  }

  static Future<void> addProject(AppProject project) async {
    final projects = await loadProjects();
    projects.insert(0, project);
    await saveProjects(projects);
  }

  static Future<void> deleteProject(String id) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.id == id);
    await saveProjects(projects);
  }
}

// ---------------------------------------------------------------------------
// KI-Services (Gemini & Groq)
// ---------------------------------------------------------------------------

const kSystemPrompt = '''
Du bist ein Generator für eigenständige mobile Web-Apps und Browser-Spiele.
Antworte AUSSCHLIESSLICH mit dem Quellcode EINER vollständigen, validen HTML5-Datei.

FORMAT (strikt einhalten):
- Die Antwort beginnt exakt mit <!DOCTYPE html> und endet exakt mit </html>.
- KEINE Markdown-Codeblöcke, KEINE Backticks (```), KEIN einleitender oder abschließender Text, KEINE Erklärungen.
- Sämtliches CSS steht in einem <style>-Tag, sämtliches JavaScript in <script>-Tags innerhalb dieser einen Datei.
- Keine externen Ressourcen: keine CDNs, keine Bibliotheken, keine Webfonts, keine Bilder oder Sounds aus dem Netz. Grafiken per Canvas, CSS, SVG oder Emoji; Sounds bei Bedarf per Web Audio API.
- Im <head>: <meta charset="utf-8">, <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"> und ein kurzer, prägnanter <title> (max. 40 Zeichen), der die App benennt.

MOBILE & TOUCH:
- Ausgelegt für Smartphones im Hochformat. Das Layout passt sich an Breite UND Höhe des Viewports an und reagiert auf das resize-Event.
- Vollständig per Touch bedienbar: Touch-Events (touchstart/touchmove/touchend) oder Pointer Events. Auf Spielflächen preventDefault() mit { passive: false } und touch-action: none, damit die Seite nicht scrollt oder zoomt.
- Für Spiele, die Richtungen oder Aktionen brauchen: gut erreichbare On-Screen-Buttons oder Wischgesten. Es darf keine Tastatur nötig sein (Tastatursteuerung höchstens zusätzlich).
- Buttons mindestens 44×44 px, gut lesbare Schriftgrößen, keine Hover-Abhängigkeiten.
- Canvas-Inhalte mit devicePixelRatio scharf darstellen.
- body mit margin: 0, user-select: none, kein Overscroll.

QUALITÄT:
- Vollständig implementiert und sofort benutzbar bzw. spielbar: keine Platzhalter, keine TODOs, kein Pseudocode.
- Keine JavaScript-Fehler. Spiele haben einen Startbildschirm, Punktestand (wo sinnvoll), Game-Over-Zustand und Neustart.
- Neustart und Zurücksetzen ausschließlich per JavaScript-Zustand, NIEMALS über location.reload() oder Seitenwechsel.
- localStorage nur innerhalb von try/catch verwenden (z. B. für Highscores).
- Modernes, ansprechendes Design mit stimmigen Farben.
- Alle Texte der App in der Sprache des Nutzer-Prompts.
''';

String buildUserPrompt(String prompt) =>
    'Erstelle folgende App bzw. folgendes Spiel als eine einzige HTML-Datei:'
    '\n\n$prompt';

class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeneratedApp {
  const GeneratedApp({required this.title, required this.html});

  final String title;
  final String html;
}

Map<String, dynamic>? _decodeJson(http.Response response) {
  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String? _apiErrorMessage(Map<String, dynamic>? data) {
  final error = data?['error'];
  if (error is String) return error;
  if (error is Map<String, dynamic>) {
    final message = error['message'];
    if (message is String) return message;
  }
  return null;
}

abstract class AiService {
  AiService() : _client = http.Client();

  final http.Client _client;

  static const _timeout = Duration(minutes: 5);

  AiProvider get provider;

  /// Schickt den Prompt an den Anbieter und liefert den rohen Antworttext.
  Future<String> requestText({
    required String apiKey,
    required String model,
    required String prompt,
  });

  /// IDs der Modelle, die sich für die Textgenerierung eignen.
  Future<List<String>> listModels(String apiKey);

  Future<GeneratedApp> generateApp({
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    final raw = await requestText(
      apiKey: apiKey,
      model: model.trim(),
      prompt: prompt,
    );
    final html = HtmlCleaner.clean(raw);
    if (html == null) {
      throw AiException(
        'Die Antwort von ${provider.label} enthielt keinen HTML-Code. '
        'Bitte erneut versuchen.',
      );
    }
    return GeneratedApp(
      title: HtmlCleaner.extractTitle(html) ?? _titleFromPrompt(prompt),
      html: html,
    );
  }

  void close() => _client.close();

  Future<http.Response> postJson(
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic> body,
  ) =>
      _send(
        _client.post(
          uri,
          headers: {'Content-Type': 'application/json', ...headers},
          body: jsonEncode(body),
        ),
      );

  Future<http.Response> getJson(Uri uri, Map<String, String> headers) =>
      _send(_client.get(uri, headers: headers));

  Future<http.Response> _send(Future<http.Response> request) async {
    try {
      return await request.timeout(_timeout);
    } on TimeoutException {
      throw AiException(
        'Zeitüberschreitung: ${provider.label} hat nicht rechtzeitig '
        'geantwortet. Bitte erneut versuchen.',
      );
    } on http.ClientException catch (e) {
      throw AiException(
        'Netzwerkfehler: ${e.message}\nBesteht eine Internetverbindung?',
      );
    }
  }

  String describeHttpError(int status, String? apiMessage, {String? model}) {
    final name = provider.label;
    final details = apiMessage == null ? '' : '\n\nDetails: $apiMessage';
    final lower = apiMessage?.toLowerCase() ?? '';

    switch (status) {
      case 400:
        if (lower.contains('api key') || lower.contains('api_key')) {
          return 'Der $name-API-Key ist ungültig. Bitte in den Einstellungen '
              'prüfen.$details';
        }
        return 'Ungültige Anfrage an $name (400).$details';
      case 401:
      case 403:
        return 'Zugriff verweigert ($status). Bitte den $name-API-Key in den '
            'Einstellungen prüfen.$details';
      case 404:
        if (model == null) return '$name: Adresse nicht gefunden (404).$details';
        return 'Das Modell „$model“ gibt es bei $name nicht (mehr). Wähle in '
            'den Einstellungen ein anderes, z. B. ${provider.defaultModel}.'
            '$details';
      case 413:
        return 'Die Anfrage ist zu groß für dein $name-Kontingent (Tokens pro '
            'Minute). Bitte den Prompt vereinfachen oder ein anderes Modell '
            'wählen.$details';
      case 429:
        return 'Kontingent oder Anfragelimit bei $name erreicht (429). Bitte '
            'kurz warten und erneut versuchen.$details';
      case 500:
      case 502:
      case 503:
      case 504:
        return '$name ist gerade überlastet ($status). Bitte später erneut '
            'versuchen.$details';
      default:
        return 'Fehler bei der Anfrage an $name (HTTP $status).$details';
    }
  }

  static String _titleFromPrompt(String prompt) {
    final singleLine = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.isEmpty) return 'Neues Projekt';
    final chars = singleLine.characters;
    return chars.length > 40 ? '${chars.take(37)}…' : singleLine;
  }
}

class GeminiService extends AiService {
  static const _host = 'generativelanguage.googleapis.com';
  static final _excludedModels = RegExp(
    'tts|image|embedding|live|audio|robotics|computer-use|transcribe',
  );

  @override
  AiProvider get provider => AiProvider.gemini;

  @override
  Future<String> requestText({
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    final modelId = model.replaceFirst(RegExp(r'^models/'), '');
    final response = await postJson(
      Uri.https(_host, '/v1beta/models/$modelId:generateContent'),
      {'x-goog-api-key': apiKey},
      {
        'systemInstruction': {
          'parts': [
            {'text': kSystemPrompt},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': buildUserPrompt(prompt)},
            ],
          },
        ],
      },
    );

    final data = _decodeJson(response);
    if (response.statusCode != 200) {
      throw AiException(
        describeHttpError(
          response.statusCode,
          _apiErrorMessage(data),
          model: modelId,
        ),
      );
    }
    if (data == null) {
      throw const AiException('Unerwartete Antwort von Gemini.');
    }

    final feedback = data['promptFeedback'];
    if (feedback is Map<String, dynamic> && feedback['blockReason'] != null) {
      throw AiException(
        'Der Prompt wurde von Gemini blockiert (${feedback['blockReason']}). '
        'Bitte formuliere ihn um.',
      );
    }

    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const AiException(
        'Gemini hat keine Antwort geliefert. Bitte erneut versuchen.',
      );
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final finishReason = candidate['finishReason'] as String?;
    final content = candidate['content'];
    final parts = content is Map<String, dynamic> && content['parts'] is List
        ? content['parts'] as List<dynamic>
        : const <dynamic>[];
    final text = parts
        .whereType<Map<String, dynamic>>()
        .where((part) => part['thought'] != true)
        .map((part) => part['text'])
        .whereType<String>()
        .join();

    if (finishReason == 'MAX_TOKENS') {
      throw const AiException(
        'Die Antwort war zu lang und wurde abgeschnitten. '
        'Bitte vereinfache den Prompt.',
      );
    }
    if (text.trim().isEmpty) {
      throw AiException(
        finishReason != null && finishReason != 'STOP'
            ? 'Gemini hat die Generierung abgebrochen ($finishReason). '
                'Bitte formuliere den Prompt um.'
            : 'Gemini hat eine leere Antwort geliefert. Bitte erneut versuchen.',
      );
    }
    return text;
  }

  @override
  Future<List<String>> listModels(String apiKey) async {
    final response = await getJson(
      Uri.https(_host, '/v1beta/models', {'pageSize': '1000'}),
      {'x-goog-api-key': apiKey},
    );
    final data = _decodeJson(response);
    if (response.statusCode != 200) {
      throw AiException(
        describeHttpError(response.statusCode, _apiErrorMessage(data)),
      );
    }

    final models = data?['models'];
    if (models is! List) return const [];
    final ids = <String>{};
    for (final model in models.whereType<Map<String, dynamic>>()) {
      final name = model['name'];
      final methods = model['supportedGenerationMethods'];
      if (name is! String || methods is! List) continue;
      final id = name.replaceFirst('models/', '');
      if (id.startsWith('gemini') &&
          methods.contains('generateContent') &&
          !_excludedModels.hasMatch(id)) {
        ids.add(id);
      }
    }
    return ids.toList()..sort();
  }
}

class GroqService extends AiService {
  static const _host = 'api.groq.com';
  static final _excludedModels = RegExp(
    'whisper|tts|orpheus|guard|playai|distil',
    caseSensitive: false,
  );

  /// Im Gratis-Tarif ist die Antwortlänge pro Minute knapp – daher kompakter Code.
  static const _systemPrompt = '$kSystemPrompt\n'
      'ANTWORTLÄNGE (wichtig):\n'
      '- Die Antwortlänge ist begrenzt. Schreibe kompakten Code ohne '
      'Kommentare und ohne überflüssige Leerzeilen.\n'
      '- Die komplette Datei muss deutlich unter 5000 Tokens bleiben.\n';

  @override
  AiProvider get provider => AiProvider.groq;

  @override
  Future<String> requestText({
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    final uri = Uri.https(_host, '/openai/v1/chat/completions');
    final headers = {'Authorization': 'Bearer $apiKey'};
    final userPrompt = buildUserPrompt(prompt);

    Map<String, dynamic> body({int? maxTokens}) => {
          'model': model,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          if (maxTokens != null) 'max_completion_tokens': maxTokens,
          if (model.startsWith('openai/gpt-oss')) 'reasoning_effort': 'low',
        };

    var response = await postJson(uri, headers, body());
    var data = _decodeJson(response);

    // Groq rechnet die maximal mögliche Antwortlänge gegen das Limit „Tokens
    // pro Minute“. Passt sie nicht hinein, mit passender Obergrenze erneut senden.
    if (response.statusCode != 200) {
      final maxTokens = fittingMaxTokens(
        _apiErrorMessage(data),
        _systemPrompt.length + userPrompt.length,
      );
      if (maxTokens != null) {
        response = await postJson(uri, headers, body(maxTokens: maxTokens));
        data = _decodeJson(response);
      }
    }

    if (response.statusCode != 200) {
      throw AiException(
        describeHttpError(
          response.statusCode,
          _apiErrorMessage(data),
          model: model,
        ),
      );
    }

    final choices = data?['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiException(
        'Groq hat keine Antwort geliefert. Bitte erneut versuchen.',
      );
    }
    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'];
    final content = message is Map<String, dynamic> ? message['content'] : null;

    if (choice['finish_reason'] == 'length') {
      throw const AiException(
        'Die Antwort hat das Groq-Limit für die Antwortlänge erreicht und '
        'wurde abgeschnitten. Bitte den Prompt vereinfachen oder in den '
        'Einstellungen Gemini wählen.',
      );
    }
    if (content is! String || content.trim().isEmpty) {
      throw const AiException(
        'Groq hat eine leere Antwort geliefert. Bitte erneut versuchen.',
      );
    }
    return content;
  }

  /// Wertet Fehler wie „Request too large … Limit 8000, Requested 66000“ aus
  /// und berechnet eine Antwort-Obergrenze, die ins Limit passt. Liefert `null`,
  /// wenn der Fehler nicht dazu passt oder kaum Platz für eine Antwort bliebe.
  static int? fittingMaxTokens(String? errorMessage, int promptChars) {
    if (errorMessage == null) return null;
    final match =
        RegExp(r'Limit (\d+), Requested (\d+)').firstMatch(errorMessage);
    if (match == null) return null;
    final limit = int.parse(match.group(1)!);
    // Vorsichtige Schätzung des Prompts: ca. 3 Zeichen pro Token.
    final maxTokens = limit - (promptChars / 3).ceil() - 256;
    return maxTokens >= 2000 ? maxTokens : null;
  }

  @override
  Future<List<String>> listModels(String apiKey) async {
    final response = await getJson(
      Uri.https(_host, '/openai/v1/models'),
      {'Authorization': 'Bearer $apiKey'},
    );
    final data = _decodeJson(response);
    if (response.statusCode != 200) {
      throw AiException(
        describeHttpError(response.statusCode, _apiErrorMessage(data)),
      );
    }

    final models = data?['data'];
    if (models is! List) return const [];
    final ids = <String>{};
    for (final model in models.whereType<Map<String, dynamic>>()) {
      final id = model['id'];
      if (id is String &&
          model['active'] != false &&
          !_excludedModels.hasMatch(id)) {
        ids.add(id);
      }
    }
    return ids.toList()..sort();
  }
}

// ---------------------------------------------------------------------------
// PromptPlay Cloud (Firebase): Gratis-Credits ohne eigenen API-Key
// ---------------------------------------------------------------------------

/// `null`, wenn Firebase nicht gestartet werden konnte (oder in Tests).
/// Dann funktioniert nur die Generierung mit eigenem API-Key.
CloudService? cloudService;

class NoCreditsException extends AiException {
  const NoCreditsException()
      : super('Keine Credits mehr – bitte im Shop aufladen.');
}

class PurchasePendingException extends AiException {
  const PurchasePendingException()
      : super(
          'Die Zahlung ist noch nicht abgeschlossen. Die Credits werden '
          'gutgeschrieben, sobald Google Play sie bestätigt.',
        );
}

class CloudService {
  static const label = 'PromptPlay Cloud';
  static const _region = 'europe-west3'; // wie in functions/index.js

  final _auth = FirebaseAuth.instance;
  final _functions = FirebaseFunctions.instanceFor(region: _region);
  Future<void>? _ready;

  /// Meldet anonym an und legt beim ersten Mal das Profil mit Startguthaben an.
  /// Parallele Aufrufe teilen sich den Vorgang; nach einem Fehler wird neu versucht.
  Future<void> ensureReady() => _ready ??= _signInAndEnsureProfile();

  Future<void> _signInAndEnsureProfile() async {
    try {
      if (_auth.currentUser == null) await _auth.signInAnonymously();
      await _functions.httpsCallable('ensureUserProfile').call<Object?>();
    } catch (e) {
      _ready = null;
      rethrow;
    }
  }

  /// Live-Kontostand aus users/{uid}; `null`, solange er unbekannt ist.
  Stream<int?> credits() => _auth.authStateChanges().asyncExpand((user) {
        if (user == null) return Stream<int?>.value(null);
        return FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .map((snap) => (snap.data()?['credits'] as num?)?.toInt());
      });

  Future<GeneratedApp> generateGame(String prompt) async {
    try {
      await ensureReady();
    } catch (e) {
      debugPrint('Anmeldung bei PromptPlay Cloud fehlgeschlagen: $e');
      throw const AiException(
        'Keine Verbindung zum PromptPlay-Server. Bitte prüfe deine '
        'Internetverbindung.',
      );
    }

    final callable = _functions.httpsCallable(
      'generateGame',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );
    try {
      final result = await callable.call<Object?>({'prompt': prompt});
      final data = Map<String, dynamic>.from(result.data as Map);
      final html = HtmlCleaner.clean(data['html'] as String? ?? '');
      if (html == null) {
        throw const AiException('Der Server hat keinen HTML-Code geliefert.');
      }
      return GeneratedApp(
        title: data['title'] as String? ?? AiService._titleFromPrompt(prompt),
        html: html,
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') throw const NoCreditsException();
      throw AiException(
        e.message ?? 'Die Cloud-Generierung ist fehlgeschlagen (${e.code}).',
      );
    }
  }

  /// Meldet eine KI-generierte App zur Prüfung (Google-Play-Pflicht für KI-Apps).
  Future<void> reportContent(AppProject project, String reason) async {
    try {
      await ensureReady();
      await _functions.httpsCallable('reportContent').call<Object?>({
        'reason': reason,
        'title': project.title,
        'prompt': project.prompt,
        'generatedBy': project.generatedBy ?? '',
        'html': project.htmlCode,
      });
    } catch (e) {
      debugPrint('Meldung fehlgeschlagen: $e');
      throw AiException(
        e is FirebaseFunctionsException && e.message != null
            ? e.message!
            : 'Die Meldung konnte nicht gesendet werden. Bitte prüfe deine '
                'Internetverbindung.',
      );
    }
  }

  /// Anonymisierte Kontokennung für Google Play (SHA-256 der UID). Der Server
  /// prüft damit, dass ein Kaufbeleg zu diesem Konto gehört.
  String? get purchaseAccountId {
    final uid = _auth.currentUser?.uid;
    return uid == null ? null : sha256.convert(utf8.encode(uid)).toString();
  }

  /// Lässt einen Google-Play-Kauf auf dem Server prüfen und gutschreiben.
  /// Liefert die neu gutgeschriebenen Credits (0, wenn schon erledigt).
  Future<int> verifyPurchase(String productId, String purchaseToken) async {
    try {
      await ensureReady();
      final result = await _functions.httpsCallable('verifyPurchase').call<Object?>({
        'productId': productId,
        'purchaseToken': purchaseToken,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      return (data['added'] as num?)?.toInt() ?? 0;
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (details is Map && details['pending'] == true) {
        throw const PurchasePendingException();
      }
      throw AiException(e.message ?? 'Der Kauf konnte nicht geprüft werden.');
    } catch (e) {
      debugPrint('Kaufprüfung fehlgeschlagen: $e');
      throw const AiException(
        'Der Kauf konnte gerade nicht geprüft werden. Deine Credits werden '
        'beim nächsten Start der App gutgeschrieben.',
      );
    }
  }

  /// Löscht Credits-Profil und anonymes Konto auf dem Server.
  Future<void> deleteAccount() async {
    if (_auth.currentUser == null) return;
    await _functions.httpsCallable('deleteAccount').call<Object?>();
    await _auth.signOut();
    _ready = null;
  }
}

// ---------------------------------------------------------------------------
// Credit-Shop (Google Play Billing)
// ---------------------------------------------------------------------------

enum StoreEventType { credited, pending, canceled, error }

class StoreEvent {
  const StoreEvent(this.type, {this.message, this.added = 0});

  final StoreEventType type;
  final String? message;
  final int added;
}

/// Was der Shop-Bildschirm vom Shop braucht (in Tests durch eine Attrappe
/// ersetzbar).
abstract class CreditShop {
  Stream<StoreEvent> get events;
  Future<ProductDetails?> loadProduct();
  Future<void> buy(ProductDetails product);
}

/// `null`, wenn Firebase nicht verfügbar ist (oder in Tests).
CreditShop? creditShop;

class CreditStore implements CreditShop {
  CreditStore(this._cloud);

  /// Muss in der Play Console als In-App-Produkt angelegt sein.
  static const productId = 'credits_20';

  final CloudService _cloud;
  final _iap = InAppPurchase.instance;
  final _events = StreamController<StoreEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  @override
  Stream<StoreEvent> get events => _events.stream;

  /// Einmal beim App-Start: Kauf-Updates empfangen und Käufe, deren Gutschrift
  /// noch aussteht (z. B. nach einem Verbindungsabbruch), erneut zustellen lassen.
  Future<void> start() async {
    _subscription ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => _events.add(
        StoreEvent(StoreEventType.error, message: 'Der Kauf ist fehlgeschlagen: $e'),
      ),
    );
    try {
      if (await _iap.isAvailable()) await _iap.restorePurchases();
    } catch (e) {
      debugPrint('Offene Käufe konnten nicht abgefragt werden: $e');
    }
  }

  @override
  Future<ProductDetails?> loadProduct() async {
    if (!await _iap.isAvailable()) return null;
    final response = await _iap.queryProductDetails({productId});
    return response.productDetails.isEmpty
        ? null
        : response.productDetails.first;
  }

  @override
  Future<void> buy(ProductDetails product) async {
    try {
      await _cloud.ensureReady();
    } catch (_) {
      throw const AiException(
        'Keine Verbindung zum PromptPlay-Server. Bitte prüfe deine '
        'Internetverbindung.',
      );
    }
    final started = await _iap.buyConsumable(
      purchaseParam: PurchaseParam(
        productDetails: product,
        applicationUserName: _cloud.purchaseAccountId,
      ),
      // Verbraucht wird auf dem Server – erst nach der Gutschrift.
      autoConsume: false,
    );
    if (!started) {
      throw const AiException('Der Kauf konnte nicht gestartet werden.');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _events.add(const StoreEvent(StoreEventType.pending));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _deliver(purchase);
        case PurchaseStatus.canceled:
          _events.add(const StoreEvent(StoreEventType.canceled));
          await _complete(purchase);
        case PurchaseStatus.error:
          _events.add(
            StoreEvent(
              StoreEventType.error,
              message: purchase.error?.message ?? 'Der Kauf ist fehlgeschlagen.',
            ),
          );
          await _complete(purchase);
      }
    }
  }

  Future<void> _deliver(PurchaseDetails purchase) async {
    try {
      final added = await _cloud.verifyPurchase(
        purchase.productID,
        purchase.verificationData.serverVerificationData,
      );
      if (added > 0) {
        _events.add(StoreEvent(StoreEventType.credited, added: added));
      }
    } on PurchasePendingException {
      _events.add(const StoreEvent(StoreEventType.pending));
      return;
    } on AiException catch (e) {
      // Nicht abschließen: Google Play stellt den Kauf erneut zu, bis die
      // Gutschrift geklappt hat.
      _events.add(StoreEvent(StoreEventType.error, message: e.message));
      return;
    }
    await _complete(purchase);
  }

  Future<void> _complete(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(purchase);
    } catch (e) {
      debugPrint('Kauf konnte nicht abgeschlossen werden: $e');
    }
  }
}

/// Öffnet den Credit-Shop als Bottom Sheet.
Future<void> showCreditStore(BuildContext context) async {
  final shop = creditShop;
  final cloud = cloudService;
  if (shop == null || cloud == null) {
    showMessage(context, 'Der Shop ist gerade nicht verfügbar.');
    return;
  }
  final openKeySettings = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CreditStoreSheet(shop: shop, credits: cloud.credits()),
  );
  if (openKeySettings == true && context.mounted) await openSettings(context);
}

class CreditStoreSheet extends StatefulWidget {
  const CreditStoreSheet({super.key, required this.shop, required this.credits});

  final CreditShop shop;
  final Stream<int?> credits;

  @override
  State<CreditStoreSheet> createState() => _CreditStoreSheetState();
}

class _CreditStoreSheetState extends State<CreditStoreSheet> {
  StreamSubscription<StoreEvent>? _eventsSubscription;
  ProductDetails? _product;
  bool _loadingProduct = true;
  bool _buying = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _eventsSubscription = widget.shop.events.listen(_onEvent);
    _loadProduct();
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    ProductDetails? product;
    try {
      product = await widget.shop.loadProduct();
    } catch (e) {
      debugPrint('Produkt konnte nicht geladen werden: $e');
    }
    if (!mounted) return;
    setState(() {
      _product = product;
      _loadingProduct = false;
    });
  }

  void _onEvent(StoreEvent event) {
    if (!mounted) return;
    setState(() {
      _buying = false;
      switch (event.type) {
        case StoreEventType.credited:
          _status = '${event.added} Credits gutgeschrieben – viel Spaß!';
          _statusIsError = false;
        case StoreEventType.pending:
          _status = 'Zahlung ausstehend. Die Credits werden gutgeschrieben, '
              'sobald Google Play sie bestätigt.';
          _statusIsError = false;
        case StoreEventType.canceled:
          _status = null;
        case StoreEventType.error:
          _status = event.message ?? 'Der Kauf ist fehlgeschlagen.';
          _statusIsError = true;
      }
    });
  }

  Future<void> _buy(ProductDetails product) async {
    setState(() {
      _buying = true;
      _status = null;
    });
    try {
      await widget.shop.buy(product);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buying = false;
        _status = e is AiException
            ? e.message
            : 'Der Kauf konnte nicht gestartet werden.';
        _statusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final product = _product;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Credit-Shop', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            StreamBuilder<int?>(
              stream: widget.credits,
              builder: (context, snapshot) => Text(
                snapshot.data == null
                    ? 'Guthaben wird geladen …'
                    : 'Dein Guthaben: ⚡ ${snapshot.data} Credits',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: const Text('⚡'),
                ),
                title: const Text('20 Spiele-Credits'),
                subtitle: const Text('1 Credit = 1 neues Spiel oder eine Mini-App'),
                trailing: product == null
                    ? null
                    : Text(product.price, style: theme.textTheme.titleMedium),
              ),
            ),
            const SizedBox(height: 16),
            if (_loadingProduct)
              const Center(child: CircularProgressIndicator())
            else if (product == null)
              Text(
                'Der Shop ist gerade nicht verfügbar. Käufe funktionieren nur '
                'in der App aus dem Google Play Store.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              )
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _buying ? null : () => _buy(product),
                icon: _buying
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shopping_cart_outlined),
                label: Text(
                  _buying ? 'Kauf läuft …' : 'Jetzt kaufen – ${product.price}',
                ),
              ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusIsError ? colors.error : colors.primary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Lieber eigenen API-Key nutzen (unbegrenzt)'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Macht aus der Modellantwort eine saubere, eigenständige HTML-Datei.
class HtmlCleaner {
  HtmlCleaner._();

  static final _thinkBlock = RegExp(
    r'<think>[\s\S]*?</think>',
    caseSensitive: false,
  );
  static final _fencedBlock = RegExp(r'```[^\n]*\n([\s\S]*?)(?:```|$)');
  static final _trailingFence = RegExp(r'\s*```\s*$');
  static final _anyTag = RegExp(r'<[a-zA-Z!][^>]*>');
  static final _viewportMeta = RegExp(
    r'''<meta[^>]+name\s*=\s*["']?viewport''',
    caseSensitive: false,
  );
  static final _headTag = RegExp(r'<head(\s[^>]*)?>', caseSensitive: false);
  static final _htmlTag = RegExp(r'<html(\s[^>]*)?>', caseSensitive: false);
  static final _titleTag = RegExp(
    r'<title[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  );

  static const _viewport =
      '<meta name="viewport" content="width=device-width, initial-scale=1, '
      'maximum-scale=1, user-scalable=no">';

  /// Gibt `null` zurück, wenn die Antwort gar kein HTML enthält.
  static String? clean(String raw) {
    // Denkprozess mancher Modelle (<think>…</think>) entfernen.
    var text = raw.replaceAll('\r\n', '\n').replaceAll(_thinkBlock, '').trim();
    final lower = text.toLowerCase();

    var start = lower.indexOf('<!doctype');
    if (start < 0) start = lower.indexOf('<html');

    if (start >= 0) {
      // Vollständiges Dokument: alles vor <!DOCTYPE/<html> und nach </html>
      // (Einleitung, Markdown-Fences, Erklärungen) abschneiden.
      final end = lower.lastIndexOf('</html>');
      text = end > start
          ? text.substring(start, end + '</html>'.length)
          : text.substring(start);
      text = text.replaceFirst(_trailingFence, '').trim();
      if (!text.toLowerCase().startsWith('<!doctype')) {
        text = '<!DOCTYPE html>\n$text';
      }
    } else {
      // Nur ein Fragment: größten Markdown-Codeblock nehmen und einbetten.
      String? best;
      for (final match in _fencedBlock.allMatches(text)) {
        final block = match.group(1)!.trim();
        if (best == null || block.length > best.length) best = block;
      }
      text = (best ?? text).replaceAll('```', '').trim();
      if (!_anyTag.hasMatch(text)) return null;
      text = _wrapFragment(text);
    }

    return _ensureViewport(text);
  }

  static String? extractTitle(String html) {
    final match = _titleTag.firstMatch(html);
    if (match == null) return null;
    final title = _decodeEntities(match.group(1)!)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isEmpty) return null;
    final chars = title.characters;
    return chars.length > 60 ? '${chars.take(57)}…' : title;
  }

  static String _ensureViewport(String html) {
    if (_viewportMeta.hasMatch(html)) return html;

    final head = _headTag.firstMatch(html);
    if (head != null) {
      return html.replaceRange(head.end, head.end, '\n$_viewport');
    }
    final htmlTag = _htmlTag.firstMatch(html);
    if (htmlTag != null) {
      return html.replaceRange(
        htmlTag.end,
        htmlTag.end,
        '\n<head>\n<meta charset="utf-8">\n$_viewport\n</head>',
      );
    }
    return html;
  }

  static String _wrapFragment(String fragment) => '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
$_viewport
<style>body { margin: 0; }</style>
</head>
<body>
$fragment
</body>
</html>''';

  static String _decodeEntities(String text) => text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}

// ---------------------------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------------------------

/// Wird über GitHub Pages aus docs/datenschutz.html bereitgestellt.
const kPrivacyPolicyUrl =
    'https://siriussagittarius.github.io/gemini-play/datenschutz.html';

/// Öffnet eine Adresse im Browser; klappt das nicht, landet sie in der
/// Zwischenablage.
Future<void> openExternalUrl(BuildContext context, String url) async {
  var opened = false;
  try {
    opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('Browser konnte nicht geöffnet werden: $e');
  }
  if (opened || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  showMessage(
    context,
    'Browser konnte nicht geöffnet werden. Die Adresse $url wurde in die '
    'Zwischenablage kopiert.',
  );
}

String formatDate(DateTime date) {
  final d = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}, '
      '${two(d.hour)}:${two(d.minute)} Uhr';
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> shareProject(BuildContext context, AppProject project) async {
  try {
    await Share.share(project.htmlCode, subject: project.title);
  } catch (e) {
    if (!context.mounted) return;
    showMessage(context, 'Teilen fehlgeschlagen: $e');
  }
}

/// Öffnet die Einstellungen. Liefert `true`, wenn gespeichert wurde.
Future<bool> openSettings(BuildContext context) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const SettingsScreen()),
  );
  return saved ?? false;
}

// ---------------------------------------------------------------------------
// Einstellungen (Anbieter, API-Key, Modell)
// ---------------------------------------------------------------------------

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyControllers = {
    for (final provider in AiProvider.values)
      provider: TextEditingController(),
  };
  final _modelControllers = {
    for (final provider in AiProvider.values)
      provider: TextEditingController(),
  };
  final _loadedModels = <AiProvider, List<String>>{};

  AiProvider _provider = AiProvider.gemini;
  bool _loading = true;
  bool _saving = false;
  bool _obscureKey = true;
  bool _fetchingModels = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      ..._keyControllers.values,
      ..._modelControllers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final provider = await AppStore.getProvider();
    for (final p in AiProvider.values) {
      _keyControllers[p]!.text = await AppStore.getApiKey(p);
      _modelControllers[p]!.text = await AppStore.getModel(p);
    }
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_loading) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    await AppStore.setProvider(_provider);
    for (final p in AiProvider.values) {
      await AppStore.setApiKey(p, _keyControllers[p]!.text);
      await AppStore.setModel(p, _modelControllers[p]!.text);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _openKeyPage() => openExternalUrl(context, _provider.keyUrl);

  Future<void> _deleteCloudAccount() async {
    final cloud = cloudService;
    if (cloud == null) return;
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cloud-Konto löschen?'),
        content: const Text(
          'Dein anonymes PromptPlay-Konto und deine restlichen Credits werden '
          'endgültig vom Server gelöscht. Deine Projekte und API-Keys auf '
          'diesem Gerät bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await cloud.deleteAccount();
      if (!mounted) return;
      showMessage(context, 'Dein Cloud-Konto wurde gelöscht.');
    } catch (e) {
      debugPrint('Konto löschen fehlgeschlagen: $e');
      if (!mounted) return;
      showMessage(
        context,
        'Löschen fehlgeschlagen. Bitte prüfe deine Internetverbindung.',
      );
    }
  }

  Future<void> _pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      showMessage(context, 'Die Zwischenablage ist leer.');
      return;
    }
    setState(() => _keyControllers[_provider]!.text = text);
    showMessage(context, 'Key eingefügt. Zum Übernehmen „Speichern“ tippen.');
  }

  Future<void> _fetchModels() async {
    final provider = _provider;
    final apiKey = _keyControllers[provider]!.text.trim();
    if (apiKey.isEmpty) {
      showMessage(context, 'Bitte zuerst den API-Key eintragen.');
      return;
    }

    setState(() => _fetchingModels = true);
    final service = provider.createService();
    try {
      final models = await service.listModels(apiKey);
      if (!mounted) return;
      setState(() => _loadedModels[provider] = models);
      showMessage(
        context,
        models.isEmpty
            ? 'Keine passenden Modelle gefunden.'
            : '${models.length} Modelle geladen. Tippe auf eines, um es zu '
                'übernehmen.',
      );
    } on AiException catch (e) {
      if (!mounted) return;
      showMessage(context, e.message);
    } finally {
      service.close();
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Einstellungen')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(top: false, child: _buildForm(context)),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final provider = _provider;
    final keyController = _keyControllers[provider]!;
    final modelController = _modelControllers[provider]!;
    final apiKey = keyController.text.trim();
    final keyWarning = apiKey.isNotEmpty && !apiKey.startsWith(provider.keyPrefix)
        ? '${provider.label}-Keys beginnen normalerweise mit '
            '„${provider.keyPrefix}“.'
        : null;
    final models = _loadedModels[provider] ?? provider.suggestedModels;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('KI-Anbieter', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<AiProvider>(
          showSelectedIcon: false,
          segments: [
            for (final p in AiProvider.values)
              ButtonSegment(value: p, label: Text(p.label), icon: Icon(p.icon)),
          ],
          selected: {provider},
          onSelectionChanged: (selection) =>
              setState(() => _provider = selection.first),
        ),
        const SizedBox(height: 8),
        Text(provider.description, style: theme.textTheme.bodySmall),
        const SizedBox(height: 24),
        Text('API-Key', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'So bekommst du einen kostenlosen Key:',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Unten auf „Key bei ${provider.vendor} holen“ tippen und '
                  'anmelden.\n'
                  '2. ${provider.createKeyStep}\n'
                  '3. Key kopieren, zurück in die App wechseln und auf '
                  '„Einfügen“ tippen.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _openKeyPage,
                  icon: const Icon(Icons.open_in_new),
                  label: Text('Key bei ${provider.vendor} holen'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: keyController,
          obscureText: _obscureKey,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '${provider.label} API-Key',
            border: const OutlineInputBorder(),
            helperText: keyWarning,
            helperMaxLines: 2,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Einfügen',
                  icon: const Icon(Icons.content_paste),
                  onPressed: _pasteKey,
                ),
                IconButton(
                  tooltip: _obscureKey ? 'Anzeigen' : 'Verbergen',
                  icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ],
            ),
          ),
        ),
        if (cloudService != null) ...[
          const SizedBox(height: 8),
          Text(
            'Der eigene Key ist optional: Ohne ihn erstellt PromptPlay deine '
            'Apps mit deinen Gratis-Credits. Mit eigenem Key erstellst du '
            'unbegrenzt.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        Text('Modell', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: modelController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Modell',
            helperText: 'Standard: ${provider.defaultModel}',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final model in models)
              ActionChip(
                label: Text(model),
                onPressed: () => setState(() => modelController.text = model),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _fetchingModels ? null : _fetchModels,
            icon: _fetchingModels
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download_outlined),
            label: const Text('Verfügbare Modelle abrufen'),
          ),
        ),
        if (provider == AiProvider.groq) ...[
          const SizedBox(height: 8),
          Text(
            'Hinweis: Im Gratis-Tarif begrenzt Groq die Tokens pro Minute '
            '(je nach Modell ca. 8.000–12.000). PromptPlay passt die '
            'Antwortlänge automatisch an. Sehr umfangreiche Spiele können '
            'trotzdem abgeschnitten werden – dann den Prompt vereinfachen '
            'oder Gemini nutzen.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        Text('Datenschutz & Konto', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Datenschutzerklärung'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => openExternalUrl(context, kPrivacyPolicyUrl),
              ),
              if (cloudService != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: const Text('Cloud-Konto & Credits löschen'),
                  subtitle: const Text(
                    'Löscht dein anonymes Konto und deine Credits auf dem Server.',
                  ),
                  onTap: _deleteCloudAccount,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Deine Projekte und API-Keys liegen nur auf diesem Gerät und werden '
          'beim Deinstallieren der App gelöscht.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _saving ? null : _save,
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 1: Dashboard / Projektliste
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AppProject> _projects = [];
  AiProvider _provider = AiProvider.gemini;
  bool _loading = true;
  bool _hasApiKey = true;
  int? _credits;
  StreamSubscription<int?>? _creditsSubscription;

  @override
  void initState() {
    super.initState();
    _refresh();
    _startCloud();
  }

  @override
  void dispose() {
    _creditsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startCloud() async {
    final cloud = cloudService;
    if (cloud == null) return;
    _creditsSubscription = cloud.credits().listen(
      (credits) {
        if (mounted) setState(() => _credits = credits);
      },
      onError: (Object e) => debugPrint('Credits nicht lesbar: $e'),
    );
    try {
      await cloud.ensureReady();
    } catch (e) {
      debugPrint('PromptPlay Cloud nicht erreichbar: $e');
    }
  }

  Future<void> _openShop() async {
    await showCreditStore(context);
    await _refresh();
  }

  Future<void> _refresh() async {
    final projects = await AppStore.loadProjects();
    final provider = await AppStore.getProvider();
    final apiKey = await AppStore.getApiKey(provider);
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _provider = provider;
      _hasApiKey = apiKey.isNotEmpty;
      _loading = false;
    });
  }

  Future<void> _openSettings() async {
    await openSettings(context);
    await _refresh();
  }

  Future<void> _createProject() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CreateScreen()),
    );
    await _refresh();
  }

  Future<void> _openProject(AppProject project) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerScreen(project: project)),
    );
  }

  Future<void> _deleteProject(AppProject project) async {
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Projekt löschen?'),
        content: Text('„${project.title}“ wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AppStore.deleteProject(project.id);
    await _refresh();
    if (!mounted) return;
    showMessage(context, '„${project.title}“ wurde gelöscht.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PromptPlay'),
        actions: [
          if (_credits != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                tooltip: 'Credit-Shop',
                label: Text('⚡ $_credits Credits'),
                onPressed: _openShop,
              ),
            ),
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Neues Projekt',
        onPressed: _createProject,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                96 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                // Mit PromptPlay Cloud braucht es erst einen Key, wenn die
                // Gratis-Credits aufgebraucht sind.
                if (!_hasApiKey && (cloudService == null || _credits == 0))
                  _buildApiKeyBanner(context),
                if (_projects.isEmpty)
                  _buildEmptyState(context)
                else
                  for (final project in _projects)
                    _buildProjectCard(context, project),
              ],
            ),
    );
  }

  Widget _buildApiKeyBanner(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasShop = cloudService != null;
    return Card(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.key, color: colors.onTertiaryContainer),
                const SizedBox(width: 12),
                Text(
                  hasShop ? 'Keine Credits mehr' : 'API-Key fehlt',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hasShop
                  ? 'Lade im Shop neue Credits auf oder trage einen eigenen '
                      'kostenlosen ${_provider.label}-API-Key ein.'
                  : 'Hinterlege deinen ${_provider.label}-API-Key, um Apps zu '
                      'generieren.',
            ),
            Align(
              alignment: Alignment.centerRight,
              child: OverflowBar(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _openSettings,
                    child: Text(hasShop ? 'Eigener Key' : 'Eintragen'),
                  ),
                  if (hasShop)
                    FilledButton(
                      onPressed: _openShop,
                      child: const Text('Zum Shop'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('Noch keine Projekte', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Tippe auf +, beschreibe deine Idee und die KI baut dir daraus '
            'ein Spiel oder eine Mini-App.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCard(BuildContext context, AppProject project) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final generatedBy = project.generatedBy;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            leading: CircleAvatar(
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
              child: const Icon(Icons.videogame_asset_outlined),
            ),
            title: Text(
              project.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatDate(project.createdAt)),
                if (generatedBy != null)
                  Text(
                    generatedBy,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                if (project.prompt.isNotEmpty)
                  Text(
                    project.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            onTap: () => _openProject(project),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 4,
              overflowSpacing: 4,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  onPressed: () => _deleteProject(project),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Löschen'),
                ),
                TextButton.icon(
                  onPressed: () => shareProject(context, project),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Teilen'),
                ),
                FilledButton.icon(
                  onPressed: () => _openProject(project),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Öffnen / Spielen'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 2: Neues Projekt
// ---------------------------------------------------------------------------

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  static const _examples = [
    'Baue mir ein Tetris für Touchscreens',
    'Erstelle ein Quiz mit 10 Fragen über das Sonnensystem',
    'Snake mit Wischgesten und Highscore',
    'Ein Pomodoro-Timer mit großen Buttons',
  ];

  final _promptController = TextEditingController();
  StreamSubscription<int?>? _creditsSubscription;
  int? _credits;
  AiService? _service;
  AiProvider? _provider;
  String? _model;
  Timer? _timer;
  bool _usesCloud = false;
  bool _outOfCredits = false;
  bool _loading = false;
  int _elapsedSeconds = 0;
  int _runId = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProviderInfo();
    _creditsSubscription = cloudService?.credits().listen(
      (credits) {
        if (mounted) setState(() => _credits = credits);
      },
      onError: (Object e) => debugPrint('Credits nicht lesbar: $e'),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service?.close();
    _creditsSubscription?.cancel();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _openShop() async {
    await showCreditStore(context);
    await _loadProviderInfo();
  }

  Future<void> _loadProviderInfo() async {
    final provider = await AppStore.getProvider();
    final model = await AppStore.getModel(provider);
    final apiKey = await AppStore.getApiKey(provider);
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _model = model;
      // Ohne eigenen Key läuft die Generierung über PromptPlay Cloud.
      _usesCloud = apiKey.isEmpty && cloudService != null;
      if (!_usesCloud) _outOfCredits = false;
    });
  }

  Future<void> _changeSettings() async {
    await openSettings(context);
    await _loadProviderInfo();
  }

  void _useExample(String example) {
    _promptController.value = TextEditingValue(
      text: example,
      selection: TextSelection.collapsed(offset: example.length),
    );
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Bitte beschreibe zuerst, was erstellt werden soll.');
      return;
    }
    FocusScope.of(context).unfocus();

    var provider = await AppStore.getProvider();
    var apiKey = await AppStore.getApiKey(provider);
    if (apiKey.isEmpty && cloudService == null) {
      // Ohne PromptPlay Cloud geht es nur mit eigenem Key.
      if (!mounted) return;
      final saved = await openSettings(context);
      await _loadProviderInfo();
      if (!saved) return;
      provider = await AppStore.getProvider();
      apiKey = await AppStore.getApiKey(provider);
      if (apiKey.isEmpty) return;
    }
    final model = await AppStore.getModel(provider);
    final cloud = apiKey.isEmpty ? cloudService : null;
    if (!mounted) return;

    // Ohne eigenen Key und ohne Guthaben direkt in den Shop.
    if (cloud != null && _credits == 0) {
      setState(() => _outOfCredits = true);
      await _openShop();
      return;
    }

    final runId = ++_runId;
    final service = cloud == null ? provider.createService() : null;
    _service = service;
    setState(() {
      _provider = provider;
      _model = model;
      _usesCloud = cloud != null;
      _outOfCredits = false;
      _loading = true;
      _error = null;
      _elapsedSeconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });

    try {
      final result = cloud != null
          ? await cloud.generateGame(prompt)
          : await service!.generateApp(
              apiKey: apiKey,
              model: model,
              prompt: prompt,
            );

      final project = AppProject(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: result.title,
        prompt: prompt,
        htmlCode: result.html,
        createdAt: DateTime.now(),
        generatedBy:
            cloud != null ? CloudService.label : '${provider.label} · $model',
      );
      if (runId != _runId) {
        // Abgebrochen: In der Cloud ist der Credit schon verbraucht, daher das
        // Ergebnis trotzdem in der Projektliste behalten.
        if (cloud != null) await AppStore.addProject(project);
        return;
      }
      await AppStore.addProject(project);
      _stopTimer();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => PlayerScreen(project: project)),
      );
    } on NoCreditsException {
      if (runId != _runId) return;
      _stopTimer();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _outOfCredits = true;
      });
      await _openShop();
    } catch (e) {
      if (runId != _runId) return;
      _stopTimer();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AiException ? e.message : 'Unerwarteter Fehler: $e';
      });
    } finally {
      service?.close();
      if (identical(_service, service)) _service = null;
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _cancel() {
    _runId++;
    _stopTimer();
    _service?.close();
    _service = null;
    setState(() => _loading = false);
  }

  Future<void> _onBackWhileLoading() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Generierung abbrechen?'),
        content: Text(
          _usesCloud
              ? 'Der Credit ist bereits verbraucht. Das Ergebnis landet '
                  'trotzdem in deiner Projektliste, sobald es fertig ist.'
              : 'Die laufende Generierung geht dabei verloren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Weiter warten'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    _cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = _provider;

    return PopScope<Object?>(
      canPop: !_loading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackWhileLoading();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Neues Projekt')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Was soll die KI für dich bauen?',
                style: theme.textTheme.titleMedium,
              ),
              if (_usesCloud)
                _buildCloudInfo(theme)
              else if (provider != null)
                Row(
                  children: [
                    Icon(provider.icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${provider.label} · $_model',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _changeSettings,
                      child: const Text('Ändern'),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _promptController,
                enabled: !_loading,
                minLines: 5,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'z. B. „Baue mir ein Tetris für Touchscreens“',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final example in _examples)
                    ActionChip(
                      label: Text(example),
                      onPressed: _loading ? null : () => _useExample(example),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (_loading)
                _buildProgress(theme)
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _generate,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Erstellen'),
                ),
              if (_usesCloud && _outOfCredits && (_credits ?? 0) == 0) ...[
                const SizedBox(height: 16),
                _buildNoCreditsCard(theme),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _buildError(theme, _error!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCloudInfo(ThemeData theme) {
    final credits = _credits;
    return Row(
      children: [
        Icon(Icons.cloud_outlined, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            credits == null
                ? CloudService.label
                : '${CloudService.label} · ⚡ $credits Credits',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        TextButton(
          onPressed: _loading ? null : _openShop,
          child: const Text('Shop'),
        ),
        TextButton(
          onPressed: _loading ? null : _changeSettings,
          child: const Text('Eigener Key'),
        ),
      ],
    );
  }

  Widget _buildNoCreditsCard(ThemeData theme) {
    final colors = theme.colorScheme;
    return Card(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Keine Credits mehr',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: colors.onTertiaryContainer),
            ),
            const SizedBox(height: 8),
            Text(
              'Lade im Shop 20 neue Credits auf – oder erstelle mit einem '
              'eigenen kostenlosen API-Key (Gemini oder Groq) unbegrenzt weiter.',
              style: TextStyle(color: colors.onTertiaryContainer),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openShop,
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('Credits kaufen'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _changeSettings,
              icon: const Icon(Icons.key),
              label: const Text('Eigenen API-Key eintragen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(ThemeData theme) {
    final name = _usesCloud ? CloudService.label : _provider?.label ?? 'Die KI';
    return Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          '$name generiert deine App … ($_elapsedSeconds s)',
          style: theme.textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Das kann je nach Umfang bis zu zwei Minuten dauern.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _cancel,
          icon: const Icon(Icons.close),
          label: const Text('Abbrechen'),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme, String message) {
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Screen 3: Player (WebView)
// ---------------------------------------------------------------------------

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.project});

  final AppProject project;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  InAppWebViewController? _controller;
  bool _fullscreen = false;

  /// Eigener Origin pro Projekt, damit localStorage (z. B. Highscores)
  /// zwischen den Projekten getrennt bleibt.
  late final WebUri _baseUrl = WebUri(
    'https://p${widget.project.id.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '')}'
    '.promptplay.local/',
  );

  @override
  void dispose() {
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _loadHtml() async {
    await _controller?.loadData(
      data: widget.project.htmlCode,
      mimeType: 'text/html',
      encoding: 'utf8',
      baseUrl: _baseUrl,
    );
  }

  Future<void> _report() async {
    final cloud = cloudService;
    if (cloud == null) {
      showMessage(
        context,
        'Melden ist gerade nicht möglich, weil keine Verbindung zum '
        'PromptPlay-Server besteht.',
      );
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const ReportDialog(),
    );
    if (reason == null || !mounted) return;

    try {
      await cloud.reportContent(widget.project, reason);
      if (!mounted) return;
      showMessage(context, 'Danke! Deine Meldung wurde übermittelt.');
    } on AiException catch (e) {
      if (!mounted) return;
      showMessage(context, e.message);
    }
  }

  Future<void> _setFullscreen(bool enabled) async {
    setState(() => _fullscreen = enabled);
    await SystemChrome.setEnabledSystemUIMode(
      enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (!enabled || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Vollbild – mit der Zurück-Geste beenden'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _setFullscreen(false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _fullscreen
            ? null
            : AppBar(
                title: Text(
                  widget.project.title,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    tooltip: 'Vollbild',
                    icon: const Icon(Icons.fullscreen),
                    onPressed: () => _setFullscreen(true),
                  ),
                  IconButton(
                    tooltip: 'Teilen',
                    icon: const Icon(Icons.share),
                    onPressed: () => shareProject(context, widget.project),
                  ),
                  PopupMenuButton<_PlayerAction>(
                    tooltip: 'Mehr',
                    onSelected: (action) {
                      switch (action) {
                        case _PlayerAction.restart:
                          _loadHtml();
                        case _PlayerAction.report:
                          _report();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _PlayerAction.restart,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.refresh),
                          title: Text('Neu starten'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _PlayerAction.report,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.flag_outlined),
                          title: Text('Inhalt melden'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        body: SafeArea(
          top: _fullscreen,
          child: InAppWebView(
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              databaseEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              supportZoom: false,
              builtInZoomControls: false,
              displayZoomControls: false,
              overScrollMode: OverScrollMode.NEVER,
            ),
            // Alle Touch-Gesten gehen direkt an die Web-App (wichtig für Spiele).
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
            onWebViewCreated: (controller) {
              _controller = controller;
              _loadHtml();
            },
            onConsoleMessage: (controller, message) {
              debugPrint('[WebView ${message.messageLevel}] ${message.message}');
            },
          ),
        ),
      ),
    );
  }
}

enum _PlayerAction { restart, report }

/// Meldung einer KI-generierten App. Liefert den Grund oder `null`.
class ReportDialog extends StatefulWidget {
  const ReportDialog({super.key});

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  static const _reasons = [
    'Anstößig oder beleidigend',
    'Gewalt oder Hass',
    'Sexuelle Inhalte',
    'Gefährlich oder illegal',
    'Funktioniert nicht',
    'Sonstiges',
  ];

  final _detailsController = TextEditingController();
  String? _reason;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  void _submit() {
    final details = _detailsController.text.trim();
    Navigator.of(context).pop(details.isEmpty ? _reason : '$_reason: $details');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Inhalt melden'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Was stimmt mit dieser KI-generierten App nicht?'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reason in _reasons)
                  ChoiceChip(
                    label: Text(reason),
                    selected: _reason == reason,
                    onSelected: (_) => setState(() => _reason = reason),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _detailsController,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            Text(
              'Mit der Meldung werden Prompt, Titel und Code dieser App zur '
              'Prüfung an uns übermittelt.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _reason == null ? null : _submit,
          child: const Text('Melden'),
        ),
      ],
    );
  }
}
