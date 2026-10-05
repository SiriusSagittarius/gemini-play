import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart' show ProductDetails;
import 'package:promptplay/help_screen.dart';
import 'package:promptplay/link_assets.dart';
import 'package:promptplay/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shop-Attrappe: Ein Kauf schreibt sofort die Credits des Pakets gut.
class FakeShop implements CreditShop {
  FakeShop(this.products);

  final List<ProductDetails> products;
  final _events = StreamController<StoreEvent>.broadcast();
  final bought = <String>[];

  @override
  Stream<StoreEvent> get events => _events.stream;

  @override
  Future<List<ProductDetails>> loadProducts() async => products;

  @override
  Future<void> buy(ProductDetails product) async {
    bought.add(product.id);
    _events.add(
      StoreEvent(StoreEventType.credited, added: kCreditPacks[product.id]!),
    );
  }
}

ProductDetails pack(String id, String price) => ProductDetails(
      id: id,
      title: id,
      description: id,
      price: price,
      rawPrice: 0,
      currencyCode: 'EUR',
    );

final allPacks = [
  pack('credits_10', '1,99 €'),
  pack('credits_30', '4,99 €'),
  pack('credits_70', '9,99 €'),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStore.projects = MemoryProjectRepository();
  });

  group('HtmlCleaner', () {
    test('entfernt Markdown-Fences und Begleittext', () {
      const raw = 'Hier ist dein Spiel:\n```html\n<!DOCTYPE html>\n'
          '<html><head><title>Snake &amp; Co</title></head>'
          '<body><script>const s = `x`;</script></body></html>\n```\n'
          'Viel Spaß!';
      final html = HtmlCleaner.clean(raw)!;

      expect(html.startsWith('<!DOCTYPE html>'), isTrue);
      expect(html.endsWith('</html>'), isTrue);
      expect(html.contains('```'), isFalse);
      expect(html.contains('const s = `x`;'), isTrue);
      expect(HtmlCleaner.extractTitle(html), 'Snake & Co');
    });

    test('ergänzt Doctype und Viewport-Meta-Tag', () {
      final html = HtmlCleaner.clean(
        '<html><head><title>Quiz</title></head><body></body></html>',
      )!;

      expect(html.startsWith('<!DOCTYPE html>'), isTrue);
      expect(html.contains('name="viewport"'), isTrue);
    });

    test('kommt mit abgeschnittenem Codeblock zurecht', () {
      final html = HtmlCleaner.clean(
        '```html\n<!DOCTYPE html><html><body>Hallo</body></html>',
      )!;

      expect(html.startsWith('<!DOCTYPE html>'), isTrue);
      expect(html.contains('```'), isFalse);
    });

    test('entfernt <think>-Blöcke von Reasoning-Modellen', () {
      final html = HtmlCleaner.clean(
        '<think>Ich baue ein <html>-Grundgerüst …</think>\n'
        '<!DOCTYPE html><html><head><title>Pong</title></head>'
        '<body></body></html>',
      )!;

      expect(html.contains('<think>'), isFalse);
      expect(html.contains('Grundgerüst'), isFalse);
      expect(HtmlCleaner.extractTitle(html), 'Pong');
    });

    test('bettet reine HTML-Fragmente in ein Dokument ein', () {
      final html = HtmlCleaner.clean('```\n<div id="app">Hi</div>\n```')!;

      expect(html.startsWith('<!DOCTYPE html>'), isTrue);
      expect(html.contains('<div id="app">Hi</div>'), isTrue);
      expect(html.contains('```'), isFalse);
    });

    test('lehnt Antworten ganz ohne HTML ab', () {
      expect(HtmlCleaner.clean('Das kann ich leider nicht erstellen.'), isNull);
    });
  });

  group('Groq-Tokenlimit', () {
    test('berechnet passende Obergrenze aus „Request too large“', () {
      const message = 'Request too large for model `openai/gpt-oss-120b` in '
          'organization `org_x` service tier `on_demand` on tokens per minute '
          '(TPM): Limit 8000, Requested 66536, please reduce your message size '
          'and try again.';

      expect(GroqService.fittingMaxTokens(message, 3000), 8000 - 1000 - 256);
    });

    test('ignoriert normale Rate-Limit-Fehler', () {
      const message = 'Rate limit reached for model `llama-3.3-70b-versatile` '
          'on tokens per minute (TPM): Limit 12000, Used 9000, Requested 5000.';

      expect(GroqService.fittingMaxTokens(message, 3000), isNull);
      expect(GroqService.fittingMaxTokens(null, 3000), isNull);
    });
  });

  test('AppProject übersteht JSON-Serialisierung', () {
    final project = AppProject(
      id: '42',
      title: 'Tetris',
      prompt: 'Baue mir ein Tetris',
      htmlCode: '<!DOCTYPE html><html></html>',
      createdAt: DateTime(2026, 10, 3, 12, 30),
      generatedBy: 'Groq · openai/gpt-oss-120b',
    );
    final copy = AppProject.fromJson(project.toJson());

    expect(copy.id, project.id);
    expect(copy.title, project.title);
    expect(copy.prompt, project.prompt);
    expect(copy.htmlCode, project.htmlCode);
    expect(copy.createdAt, project.createdAt);
    expect(copy.generatedBy, project.generatedBy);
  });

  test('AppStore übernimmt den bisher gespeicherten Gemini-Key', () async {
    SharedPreferences.setMockInitialValues({'gemini_api_key': 'AIzaAlt'});

    expect(await AppStore.getProvider(), AiProvider.gemini);
    expect(await AppStore.getApiKey(AiProvider.gemini), 'AIzaAlt');
    expect(await AppStore.getApiKey(AiProvider.groq), '');
    expect(await AppStore.getModel(AiProvider.groq), 'openai/gpt-oss-120b');
  });

  testWidgets('Dashboard zeigt leere Liste und API-Key-Hinweis',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const PromptPlayApp());
    await tester.pumpAndSettle();

    expect(find.text('Noch keine Projekte'), findsOneWidget);
    expect(find.text('API-Key fehlt'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('Credit-Shop zeigt drei Pakete und schreibt einen Kauf gut',
      (tester) async {
    final shop = FakeShop(allPacks);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreditStoreSheet(shop: shop, credits: Stream.value(0)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dein Guthaben: ⚡ 0 Credits'), findsOneWidget);
    expect(find.text('10 Credits'), findsOneWidget);
    expect(find.text('30 Credits'), findsOneWidget);
    expect(find.text('70 Credits'), findsOneWidget);
    expect(find.text('Bester Preis pro Credit'), findsOneWidget);
    expect(find.text('Erst mit Google anmelden'), findsNothing);

    await tester.tap(find.text('4,99 €'));
    await tester.pumpAndSettle();

    expect(shop.bought, ['credits_30']);
    expect(find.text('30 Credits gutgeschrieben – viel Spaß!'), findsOneWidget);
  });

  testWidgets('Credit-Shop meldet, wenn keine Pakete verfügbar sind',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreditStoreSheet(shop: FakeShop(const []), credits: Stream.value(5)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Der Shop ist gerade nicht verfügbar'), findsOneWidget);
  });

  testWidgets('Ohne Google-Anmeldung verlangt der Shop zuerst die Anmeldung',
      (tester) async {
    final shop = FakeShop(allPacks);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreditStoreSheet(
            shop: shop,
            credits: Stream.value(0),
            requiresSignIn: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Erst mit Google anmelden'), findsOneWidget);
    expect(find.text('1,99 €'), findsOneWidget);
    expect(shop.bought, isEmpty);
  });

  group('Größen, Weiterbauen und Grafiken', () {
    test('Kosten wie auf dem Server', () {
      expect([for (final s in GameSize.values) s.credits], [1, 2, 5]);
      expect(extendCost(40000), 1);
      expect(extendCost(40001), 2);
      expect(extendCost(100001), 3);
      expect(
        const GenerationRequest(prompt: 'x', size: GameSize.large).cost,
        5,
      );
      expect(GenerationRequest(prompt: 'x', baseHtml: 'a' * 50000).cost, 2);
    });

    test('System-Anweisung enthält Größe, Weiterbauen und Bildnamen', () {
      final created = buildSystemInstruction(
        const GenerationRequest(
          prompt: 'Moorhuhn',
          size: GameSize.medium,
          images: [GameImage(name: 'huhn', mimeType: 'image/png', data: 'AAA')],
        ),
      );
      expect(created, contains('UMFANG: Mittel'));
      expect(created, contains('window.ASSETS["huhn"]'));
      expect(created, isNot(contains('WEITERBAUEN')));

      final extended = buildSystemInstruction(
        const GenerationRequest(prompt: 'Level 2', baseHtml: '<html></html>'),
      );
      expect(extended, contains('WEITERBAUEN'));
      expect(extended, isNot(contains('UMFANG')));
    });

    test('Familien-Modus: kindgerechte Vorgaben, bleibt im Projekt gespeichert', () {
      final kid = buildSystemInstruction(
        const GenerationRequest(prompt: 'Moorhuhn', kidSafe: true),
      );
      expect(kid, contains('KINDGERECHT'));
      expect(kid, contains('Fotos von Vögeln'));
      expect(
        buildSystemInstruction(const GenerationRequest(prompt: 'Moorhuhn')),
        isNot(contains('KINDGERECHT')),
      );
      expect(kKidSafeSafetySettings, hasLength(4));

      final project = AppProject(
        id: 'k',
        title: 'Zahlenspiel',
        prompt: 'Zählen',
        htmlCode: '<html></html>',
        createdAt: DateTime(2026, 10, 4),
        kidSafe: true,
      );
      expect(AppProject.fromJson(project.toJson()).kidSafe, isTrue);
      expect(project.copyWith(note: 'Level 2').kidSafe, isTrue);
    });

    test('Grafiken werden eingebettet und vor dem Weiterbauen entfernt', () {
      const image = GameImage(name: 'huhn', mimeType: 'image/png', data: 'AAAA');
      const html = '<!DOCTYPE html><html><head><title>Moorhuhn</title></head></html>';
      final withAssets = GameAssets.inject(html, [image]);

      expect(withAssets, contains('window.ASSETS={"huhn":"data:image/png;base64,AAAA"}'));
      expect(withAssets.indexOf('promptplay-assets'), lessThan(withAssets.indexOf('<title>')));
      expect(GameAssets.strip(withAssets), html);
      expect(
        buildUserText(GenerationRequest(prompt: 'Level 2', baseHtml: withAssets)),
        isNot(contains('base64')),
      );
      expect(HtmlCleaner.clean(withAssets), isNot(contains('promptplay-assets')));
    });

    test('Bildnamen und Bildformate', () {
      expect(GameImage.sanitizeName('Böses Huhn (1).PNG'), 'boeses_huhn_1_png');
      expect(GameImage.sanitizeName('!!!'), 'bild');
      expect(GameImage.sanitizeName('x' * 50).length, 30);
      expect(GameImage.detectMimeType([0x89, 0x50, 0x4E, 0x47, 0, 0]), 'image/png');
      expect(GameImage.detectMimeType([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
      expect(
        GameImage.detectMimeType('RIFF0000WEBPVP8 '.codeUnits),
        'image/webp',
      );
      expect(GameImage.detectMimeType('GIF89a'.codeUnits), isNull);
    });

    test('Restzeit: Standardwerte und Lernen aus echten Dauern', () async {
      expect(await AppStore.expectedSeconds('cloud', 'small'), 35);
      expect(await AppStore.expectedSeconds('cloud', 'large'), 180);
      expect(await AppStore.expectedSeconds('groq', 'small'), 12);
      await AppStore.recordDuration('cloud', 'small', 80);
      expect(await AppStore.expectedSeconds('cloud', 'small'), 50);
      expect(formatDuration(45), '45 s');
      expect(formatDuration(90), '1 min 30 s');
      expect(formatDuration(120), '2 min');
    });
  });

  group('Three.js und Vorlagen-Links', () {
    test('Vorlagen-Links werden geprüft', () {
      final ok = parseSourceLinks(
        ' https://threejs.org/examples/#webgl_materials_car\n'
        'https://threejs.org/examples/#webgl_materials_car  http://example.com/a ',
      );
      expect(ok.error, isNull);
      expect(ok.urls, [
        'https://threejs.org/examples/#webgl_materials_car',
        'http://example.com/a',
      ]);
      expect(parseSourceLinks('').urls, isEmpty);
      expect(parseSourceLinks('threejs.org').error, contains('kein gültiger Link'));
      expect(parseSourceLinks('ftp://a.de/x').error, contains('kein gültiger Link'));
      expect(parseSourceLinks('http://localhost/x').error, contains('kein gültiger Link'));
      expect(
        parseSourceLinks('https://a.de/1 https://a.de/2 https://a.de/3 https://a.de/4').error,
        contains('Höchstens 3'),
      );
    });

    test('Vorlagen kosten 1 Credit extra und landen in Anweisung und Nachricht', () {
      const sources = ['https://threejs.org/examples/'];
      const request = GenerationRequest(prompt: 'Rennspiel', size: GameSize.large, sources: sources);
      expect(request.cost, 6);
      expect(
        GenerationRequest(prompt: 'x', baseHtml: 'a' * 50000, sources: sources).cost,
        3,
      );
      expect(buildSystemInstruction(request), contains('QUELLEN ALS VORLAGE'));
      expect(
        buildUserText(request),
        endsWith('Quellen (Vorlagen):\n- https://threejs.org/examples/'),
      );
      const plain = GenerationRequest(prompt: 'Rennspiel');
      expect(buildSystemInstruction(plain), isNot(contains('QUELLEN ALS VORLAGE')));
      expect(buildSystemInstruction(plain), contains('3D MIT THREE.JS'));
      expect(buildSystemInstruction(plain), contains('Keine sexuellen Inhalte'));
    });

    test('Three.js wird nur bei Bedarf eingebettet und nicht gespeichert', () {
      const game = '<!DOCTYPE html><html><head><title>3D</title></head>'
          '<body><script>const scene = new THREE.Scene();</script></body></html>';
      const flat = '<!DOCTYPE html><html><head><title>2D</title></head>'
          '<body><p>LEVEL THREE</p></body></html>';

      expect(GameLibraries.usesThree(game), isTrue);
      expect(GameLibraries.usesThree(flat), isFalse);
      expect(GameLibraries.injectThree(flat, 'var THREE={};'), flat);

      final withThree = GameLibraries.injectThree(game, 'var THREE={};"</script>"');
      expect(withThree.indexOf('promptplay-three'), lessThan(withThree.indexOf('<title>')));
      expect(withThree, contains(r'"<\/script>"'));
      expect(GameLibraries.strip(withThree), game);
      expect(HtmlCleaner.clean(withThree), isNot(contains('promptplay-three')));
    });

    test('Spiele laden Three.js nicht aus dem Netz, sondern nutzen das eingebaute', () {
      const html = '''<!DOCTYPE html><html><head>
<script src="https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.min.js"></script>
<script type="importmap">{"imports":{"three":"https://unpkg.com/three@0.160.0/build/three.module.js"}}</script>
</head><body>
<script type="module">
import * as THREE from 'three';
import { Scene, Mesh as M } from "https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js";
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
</script></body></html>''';
      final cleaned = HtmlCleaner.useBundledThree(html);

      expect(cleaned, isNot(contains('cdn.jsdelivr.net/npm/three@0.160.0/build/three.min.js')));
      expect(cleaned, isNot(contains('importmap')));
      expect(cleaned, isNot(contains("import * as THREE")));
      expect(cleaned, contains('const { Scene, Mesh: M } = THREE;'));
      // Addons stecken ebenfalls in THREE (fehlende sind dann nur undefined).
      expect(cleaned, contains('const { OrbitControls } = THREE;'));
      expect(cleaned, isNot(contains("from 'three/addons")));
      expect(GameLibraries.usesThree(cleaned), isTrue);
    });

    test('Die eingebaute Bibliothek stellt THREE und PromptPlay bereit', () async {
      const game = '<html><head></head><body><script>new THREE.Scene()</script></body></html>';
      final html = await GameLibraries.inject(game);
      expect(html, contains('<script id="promptplay-three">var THREE='));
      expect(html, contains('globalThis.PromptPlay'));
      expect(html, contains('SPDX-License-Identifier: MIT'));
      expect(
        GameLibraries.usesThree('<script>PromptPlay.loadModel("auto")</script>'),
        isTrue,
      );
    });
  });

  group('Dateien aus Links', () {
    /// Kleinste gültige GLB-Datei mit benannten Teilen.
    Uint8List glb() {
      final json = utf8.encode(jsonEncode({
        'asset': {'version': '2.0'},
        'nodes': [
          {'name': 'body'},
          {'name': 'wheel_fl'},
          {'name': 'wheel_fl'},
          {'name': ''},
        ],
        'materials': [
          {'name': 'Body_Color'},
        ],
      }));
      final padded = [...json, ...List.filled((4 - json.length % 4) % 4, 0x20)];
      final header = ByteData(20)
        ..setUint32(0, 0x46546C67, Endian.little) // „glTF“
        ..setUint32(4, 2, Endian.little)
        ..setUint32(8, 20 + padded.length, Endian.little)
        ..setUint32(12, padded.length, Endian.little)
        ..setUint32(16, 0x4E4F534A, Endian.little); // „JSON“
      return Uint8List.fromList([...header.buffer.asUint8List(), ...padded]);
    }

    final hdr = Uint8List.fromList(utf8.encode('#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n'));
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    test('Beispiel-Links zeigen auf die Seite mit dem Code', () {
      expect(
        LinkAssetFetcher.normalize(Uri.parse('https://threejs.org/examples/#webgl_materials_car')).toString(),
        'https://threejs.org/examples/webgl_materials_car.html',
      );
      expect(
        LinkAssetFetcher.normalize(Uri.parse(
          'https://github.com/mrdoob/three.js/blob/dev/examples/models/gltf/ferrari.glb',
        )).toString(),
        'https://raw.githubusercontent.com/mrdoob/three.js/dev/examples/models/gltf/ferrari.glb',
      );
      expect(
        LinkAssetFetcher.normalize(Uri.parse('https://example.com/a.html#x')).toString(),
        'https://example.com/a.html',
      );
    });

    test('lädt Modelle, HDR und Texturen einer Beispielseite', () async {
      const page = '''<div id="info"><a href="#">three.js</a> - car materials<br/>
Ferrari 458 Italia model by <a href="x">vicent091036</a></div>
<img src="files/logo.png">
<script type="module">
new HDRLoader().load('textures/equirectangular/venice_sunset_1k.hdr');
loader.load('models/gltf/ferrari.glb');
const ao = textureLoader.load('models/gltf/ferrari_ao.png');
const road = textureLoader.load('textures/asphalt.png');
gltf.load("models/gltf/scene.gltf");
</script>''';
      final requested = <String>[];
      final client = MockClient((request) async {
        requested.add(request.url.toString());
        return switch (request.url.path) {
          '/examples/webgl_materials_car.html' => http.Response(page, 200),
          '/examples/models/gltf/ferrari.glb' => http.Response.bytes(glb(), 200),
          '/examples/textures/equirectangular/venice_sunset_1k.hdr' => http.Response.bytes(hdr, 200),
          '/examples/textures/asphalt.png' => http.Response.bytes(png, 200),
          _ => http.Response('nicht gefunden', 404),
        };
      });

      final result = await LinkAssetFetcher(client: client)
          .fetch('https://threejs.org/examples/#webgl_materials_car');

      expect([for (final f in result.files) f.fileName],
          ['ferrari.glb', 'venice_sunset_1k.hdr', 'asphalt.png']);
      expect([for (final f in result.files) f.mimeType], [kModelMimeType, kHdrMimeType, 'image/png']);
      expect(result.files.first.info, contains('benannte Teile: body, wheel_fl'));
      expect(result.files.first.info, contains('Materialien: Body_Color'));
      expect(result.credit, 'Ferrari 458 Italia model by vicent091036');
      // Schattenbilder und .gltf werden nicht übernommen.
      expect(result.skipped, [
        'ferrari_ao.png: Schattenbild – das Spiel erzeugt eigene Schatten',
        'scene.gltf: .gltf wird nicht unterstützt, nur .glb',
      ]);
      expect(requested, isNot(contains(endsWith('ferrari_ao.png'))));
      // Logos auf normalen Seiten werden nicht übernommen.
      expect(requested, isNot(contains(endsWith('logo.png'))));
    });

    test('direkter Link, unbekanntes Format und zu große Dateien', () async {
      final client = MockClient((request) async => switch (request.url.path) {
            '/auto.glb' => http.Response.bytes(glb(), 200),
            '/kaputt.glb' => http.Response('kein Modell', 200),
            '/riesig.glb' => http.Response.bytes(
                Uint8List(LinkAssetFetcher.maxFileBytes + 1), 200),
            _ => http.Response('', 404),
          });
      final fetcher = LinkAssetFetcher(client: client);

      final direct = await fetcher.fetch('https://example.com/auto.glb');
      expect(direct.files.single.mimeType, kModelMimeType);
      await expectLater(
        fetcher.fetch('https://example.com/kaputt.glb'),
        throwsA(isA<LinkAssetException>().having((e) => e.message, 'message', 'unbekanntes Dateiformat')),
      );
      await expectLater(
        fetcher.fetch('https://example.com/riesig.glb'),
        throwsA(isA<LinkAssetException>().having((e) => e.message, 'message', contains('größer als'))),
      );
      await expectLater(
        fetcher.fetch('https://example.com/fehlt.html'),
        throwsA(isA<LinkAssetException>()),
      );
    });

    test('Dateien aus Links gehen nur als Beschreibung an die KI', () {
      const own = GameImage(name: 'huhn', mimeType: 'image/png', data: 'AAA');
      const model = GameImage(
        name: 'ferrari',
        mimeType: kModelMimeType,
        data: 'BBB',
        source: 'https://threejs.org/examples/models/gltf/ferrari.glb',
        info: '3D-Modell (glTF); benannte Teile: wheel_fl',
      );
      const texture = GameImage(
        name: 'ferrari_ao',
        mimeType: 'image/png',
        data: 'CCC',
        source: 'https://threejs.org/examples/models/gltf/ferrari_ao.png',
      );
      const request = GenerationRequest(prompt: 'Rennspiel', images: [own, model, texture]);

      expect([for (final i in request.ownImages) i.name], ['huhn']);
      expect([for (final i in request.linkFiles) i.name], ['ferrari', 'ferrari_ao']);
      final instruction = buildSystemInstruction(request);
      expect(instruction, contains('EINGEBETTETE DATEIEN'));
      expect(instruction, contains('- 3D-Modell "ferrari": 3D-Modell (glTF); benannte Teile: wheel_fl'));
      expect(instruction, contains('- Textur "ferrari_ao"'));
      expect(instruction, contains('PromptPlay.loadModel("NAME")'));
      expect(instruction, contains('Der Nutzer stellt diese Bilder bereit: huhn.'));

      final restored = GameImage.fromJson(jsonDecode(jsonEncode(model.toJson())) as Map<String, dynamic>);
      expect(restored.source, model.source);
      expect(restored.info, model.info);
      expect(restored.isModel, isTrue);
      expect(restored.isOwnImage, isFalse);
    });
  });

  group('Projektspeicher', () {
    test('speichert Grafiken und Versionen getrennt vom Projekt', () async {
      final project = AppProject(
        id: '1',
        title: 'Moorhuhn',
        prompt: 'Moorhuhn',
        htmlCode: '<html>v2</html>',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 4),
        note: 'Level 2',
        assetNames: const ['huhn'],
        versionCount: 1,
      );
      await AppStore.saveProject(
        project,
        assets: const [GameImage(name: 'huhn', mimeType: 'image/png', data: 'AAA')],
        versions: [
          ProjectVersion(htmlCode: '<html>v1</html>', createdAt: DateTime(2026, 10, 1)),
        ],
      );

      final loaded = (await AppStore.loadProjects()).single;
      expect(loaded.note, 'Level 2');
      expect(loaded.assetNames, ['huhn']);
      expect(loaded.versionCount, 1);
      expect((await AppStore.loadAssets('1')).single.name, 'huhn');
      expect((await AppStore.loadVersions('1')).single.htmlCode, '<html>v1</html>');
    });

    test('übernimmt Projekte aus Version 1.1 (shared_preferences)', () async {
      final old = AppProject(
        id: 'alt',
        title: 'Snake',
        prompt: 'Snake',
        htmlCode: '<html></html>',
        createdAt: DateTime(2026, 9, 1),
      );
      SharedPreferences.setMockInitialValues({
        'projects': jsonEncode([old.toJson()]),
      });

      final loaded = await AppStore.loadProjects();
      expect(loaded.single.title, 'Snake');
      expect(loaded.single.updatedAt, old.createdAt);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('projects'), isNull);
    });
  });

  testWidgets('Hilfe-Seite liefert einen Beispiel-Wunsch zurück', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
            child: const Text('Hilfe öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Hilfe öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('Beispiel: Tetris bauen'), findsOneWidget);
    await tester.tap(find.text('Beispiel: Tetris bauen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen').first);
    await tester.pumpAndSettle();

    expect(result, startsWith('Baue mir ein Tetris für Touchscreens'));
  });

  testWidgets('Mit Groq weist der Erstellen-Bildschirm auf „nur Gemini“ hin',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'ai_provider': 'groq',
      'groq_api_key': 'gsk_test',
    });
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CreateScreen()));
    await tester.pumpAndSettle();

    expect(find.text(kImagesNeedGemini), findsOneWidget);
    // Dateien aus Links gehen auch mit Groq, nur das Lesen der Seite nicht.
    expect(find.textContaining('Mit Groq liest die KI die Seite nicht mit'), findsOneWidget);
    expect(find.text('Dateien übernehmen'), findsOneWidget);
    expect(find.text('Bilder hinzufügen'), findsNothing);
    expect(find.text('Klein'), findsOneWidget);
    expect(find.text('Groß'), findsOneWidget);
  });

  testWidgets('Mit Gemini lassen sich eigene Grafiken hinzufügen',
      (tester) async {
    SharedPreferences.setMockInitialValues({'gemini_api_key': 'AIzaTest'});
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CreateScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Bilder hinzufügen'), findsOneWidget);
    expect(find.text(kImagesNeedGemini), findsNothing);
    expect(find.text('Kindgerecht (Familien-Modus)'), findsOneWidget);
    expect(find.text('Vorlagen und 3D-Modelle aus dem Netz (optional)'), findsOneWidget);
    expect(find.textContaining('Gemini liest die Seite zusätzlich als Vorlage'), findsOneWidget);

    // Ungültiger Link: Fehlermeldung statt Anfrage.
    await tester.enterText(find.byType(TextField).first, 'Ein 3D-Rennspiel');
    await tester.enterText(find.byType(TextField).last, 'threejs.org');
    await tester.tap(find.text('Erstellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('kein gültiger Link'), findsOneWidget);
  });

  testWidgets('Meldedialog verlangt einen Grund und liefert ihn mit Details',
      (tester) async {
    String? result = 'unverändert';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => const ReportDialog(),
              );
            },
            child: const Text('Melden öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Melden öffnen'));
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Melden');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(find.text('Gewalt oder Hass'));
    await tester.enterText(find.byType(TextField), 'zeigt Gewalt');
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(result, 'Gewalt oder Hass: zeigt Gewalt');
  });

  testWidgets('Einstellungen bieten Key-Button je Anbieter und speichern',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openSettings(context),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('Key bei Google AI Studio holen'), findsOneWidget);

    await tester.tap(find.text('Groq'));
    await tester.pumpAndSettle();
    expect(find.text('Key bei GroqCloud holen'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'gsk_test');
    await tester.scrollUntilVisible(
      find.text('Speichern'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(await AppStore.getProvider(), AiProvider.groq);
    expect(await AppStore.getApiKey(AiProvider.groq), 'gsk_test');
  });
}
