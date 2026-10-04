import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart' show ProductDetails;
import 'package:promptplay/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shop-Attrappe: Ein Kauf schreibt sofort 20 Credits gut.
class FakeShop implements CreditShop {
  FakeShop(this.product);

  final ProductDetails? product;
  final _events = StreamController<StoreEvent>.broadcast();
  int purchases = 0;

  @override
  Stream<StoreEvent> get events => _events.stream;

  @override
  Future<ProductDetails?> loadProduct() async => product;

  @override
  Future<void> buy(ProductDetails product) async {
    purchases++;
    _events.add(const StoreEvent(StoreEventType.credited, added: 20));
  }
}

final credits20 = ProductDetails(
  id: 'credits_20',
  title: '20 Spiele-Credits',
  description: '20 Credits',
  price: '1,99 €',
  rawPrice: 1.99,
  currencyCode: 'EUR',
);

void main() {
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

  testWidgets('Credit-Shop zeigt Guthaben und Preis und schreibt Kauf gut',
      (tester) async {
    final shop = FakeShop(credits20);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreditStoreSheet(shop: shop, credits: Stream.value(0)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dein Guthaben: ⚡ 0 Credits'), findsOneWidget);
    expect(find.text('20 Spiele-Credits'), findsOneWidget);
    expect(find.text('Jetzt kaufen – 1,99 €'), findsOneWidget);

    await tester.tap(find.text('Jetzt kaufen – 1,99 €'));
    await tester.pumpAndSettle();

    expect(shop.purchases, 1);
    expect(find.text('20 Credits gutgeschrieben – viel Spaß!'), findsOneWidget);
  });

  testWidgets('Credit-Shop meldet, wenn kein Produkt verfügbar ist',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreditStoreSheet(shop: FakeShop(null), credits: Stream.value(5)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Der Shop ist gerade nicht verfügbar'), findsOneWidget);
    expect(find.textContaining('Jetzt kaufen'), findsNothing);
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
