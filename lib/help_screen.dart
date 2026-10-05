import 'package:flutter/material.dart';

/// Hilfe & Beispiele. Tippt man bei einem Beispiel auf „Übernehmen“, schließt
/// sich die Seite und liefert den Beispiel-Wunsch zurück.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hilfe & Beispiele')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: const [
            _Section(
              icon: Icons.auto_awesome,
              title: 'So funktioniert PromptPlay',
              children: [
                _Steps([
                  'Beschreibe deine Idee in ganz normalen Worten.',
                  'Wähle die Größe: Klein, Mittel oder Groß.',
                  'Tippe auf „Erstellen“ – nach etwa einer halben bis zwei '
                      'Minuten ist dein Spiel fertig.',
                  'Spielen, teilen oder mit „Weiterbauen“ Schritt für Schritt '
                      'verbessern.',
                ]),
              ],
            ),
            _Section(
              icon: Icons.grid_view_rounded,
              title: 'Beispiel: Tetris bauen',
              children: [
                _Paragraph('1. Wunsch eingeben, zum Beispiel:'),
                _ExamplePrompt(
                  'Baue mir ein Tetris für Touchscreens. Wischen nach links oder '
                  'rechts verschiebt den Stein, Tippen dreht ihn, Wischen nach '
                  'unten lässt ihn fallen. Mit Punktestand, Vorschau auf den '
                  'nächsten Stein und Highscore.',
                ),
                _Paragraph(
                  '2. Größe „Klein“ wählen – für ein klassisches Tetris reicht das.',
                ),
                _Paragraph('3. „Erstellen“ tippen und losspielen.'),
                _Paragraph(
                  '4. Am nächsten Tag weiterbauen, Schritt für Schritt, zum Beispiel:',
                ),
                _ExamplePrompt(
                  'Alle 10 Reihen steigt das Level, die Steine fallen schneller '
                  'und jedes Level hat eine eigene Hintergrundfarbe.',
                ),
                _ExamplePrompt(
                  'Füge Soundeffekte beim Drehen und beim Abräumen von Reihen hinzu.',
                ),
                _ExamplePrompt(
                  'Gib dem Spiel einen Neon-Look mit leuchtenden Steinen.',
                ),
                _Paragraph(
                  'Jeder Schritt wird als eigene Version gespeichert. Über '
                  '⋮ → „Versionen“ kommst du jederzeit zurück.',
                ),
              ],
            ),
            _Section(
              icon: Icons.lightbulb_outline,
              title: 'Tipps für gute Wünsche',
              children: [
                _Bullets([
                  'Sag, wie gesteuert wird: Wischen, Tippen, Buttons oder Neigen.',
                  'Nenne Ziel und Regeln: Punkte, Leben, Zeitlimit, Level.',
                  'Beschreibe den Look: Farben, Retro, Neon, Comic, Weltraum …',
                  'Fang klein an und baue dann weiter – das klappt besser als '
                      'alles auf einmal.',
                  'Beschreibe Fehler beim Weiterbauen ganz konkret, z. B. „Am '
                      'rechten Rand lässt sich der Stein nicht drehen.“',
                ]),
              ],
            ),
            _Section(
              icon: Icons.sports_esports_outlined,
              title: 'Was ist möglich?',
              children: [
                _Paragraph('Arcade-Klassiker – Tetris, Snake, Breakout, Flappy Bird, Space Invaders:'),
                _ExamplePrompt(
                  'Ein Breakout-Spiel: Schläger mit dem Finger ziehen, bunte '
                  'Steine, 3 Leben und Power-ups, die aus Steinen fallen.',
                ),
                _Paragraph('Schießbude und Geschicklichkeit – zum Beispiel wie Moorhuhn:'),
                _ExamplePrompt(
                  'Ein Moorhuhn-Spiel: Hühner fliegen über den Bildschirm, '
                  'antippen zum Treffen, 90 Sekunden Zeit, weiter entfernte '
                  'Hühner geben mehr Punkte.',
                ),
                _Paragraph('Rennspiele von oben (am besten Größe „Groß“):'),
                _ExamplePrompt(
                  'Ein Mini-Rennspiel von oben: Auto per Touch lenken, Gegner '
                  'überholen, 3 Strecken mit steigender Schwierigkeit, '
                  'Rundenzeiten und Highscore.',
                ),
                _Paragraph('Quiz und Lernspiele:'),
                _ExamplePrompt(
                  'Ein Quiz mit 10 Fragen über das Sonnensystem, mit einer '
                  'kurzen Erklärung nach jeder Antwort.',
                ),
                _Paragraph('Rätsel und Denkspiele – Memory, Sudoku, 2048:'),
                _ExamplePrompt(
                  'Ein Memory-Spiel mit Tier-Emojis und 3 Schwierigkeitsstufen.',
                ),
                _Paragraph('Kleine Helfer – Timer, Würfel, Zähler, Listen:'),
                _ExamplePrompt(
                  'Eine Würfel-App für Brettspiele mit 1 bis 6 Würfeln und '
                  'Schüttel-Animation.',
                ),
              ],
            ),
            _Section(
              icon: Icons.view_in_ar_outlined,
              title: '3D-Modelle, Sounds und Vorlagen aus dem Netz',
              children: [
                _Bullets([
                  'Für 3D-Spiele ist Three.js fest eingebaut – die KI nutzt es '
                      'automatisch, wenn du ein 3D-Spiel möchtest. Das läuft '
                      'auch offline.',
                  '„Quellen durchsuchen“ öffnet Gratis-Quellen wie Kenney (3D-Modelle, '
                      'Sounds, 2D-Grafiken), Poly Haven (HDR-Himmel) und ambientCG '
                      '(Texturen) – alle CC0, also frei nutzbar, auch zum Teilen.',
                  'Dort auf „Download“ tippen oder unten „Diese Seite übernehmen“. Bei '
                      'Paketen wählst du mit Vorschau aus, was ins Spiel soll – z. B. '
                      'Rennautos und Streckenteile aus dem Kenney Racing Kit.',
                  'Lange auf ein beliebiges Bild drücken → „Nur als Referenz“: Die KI '
                      'orientiert sich an Stil und Farben, das Bild selbst kommt nicht '
                      'ins Spiel. So kannst du auch geschützte Bilder als Vorlage nutzen.',
                  'Mit Gemini liest die KI eingetragene Seiten zusätzlich als Vorlage – '
                      'in der PromptPlay Cloud kostet das 1 Credit extra.',
                  'Bei anderen Quellen gilt die Lizenz des Urhebers. Marken wie '
                      'Automarken oder bekannte Figuren sind zusätzlich geschützt – '
                      'zum privaten Spielen kein Problem, zum Veröffentlichen schon.',
                ]),
                _Paragraph('Zum Beispiel mit dem Link threejs.org/examples/#webgl_materials_car:'),
                _ExamplePrompt(
                  'Ein 3D-Rennspiel mit dem Ferrari: Kamera hinter dem Auto, Gas '
                  'und Lenken per Touch, die Räder drehen sich, Rundstrecke mit '
                  'Leitplanken, Rundenzeit und 3 Gegner.',
                ),
              ],
            ),
            _Section(
              icon: Icons.family_restroom,
              title: 'Familien-Modus: Spiele für Kinder',
              children: [
                _Bullets([
                  'Schalte beim Erstellen „Kindgerecht (Familien-Modus)“ ein, um '
                      'Spiele für Kinder von etwa 6 bis 12 Jahren zu bauen.',
                  'Die KI verzichtet dann auf Gewalt, Gruseliges und Kaufmechaniken, '
                      'nutzt einfache Sprache und große Bedienelemente; dazu laufen '
                      'die strengsten Sicherheitsfilter von Google.',
                  'Ungeeignete Wünsche werden kindgerecht umgesetzt – aus „Vögel '
                      'abschießen“ wird z. B. „Vögel fotografieren“.',
                  'Ein kindgerechtes Spiel bleibt auch beim Weiterbauen kindgerecht.',
                  'Eine KI kann sich irren: Schau dir das Spiel kurz selbst an, '
                      'bevor du es deinem Kind gibst.',
                ]),
                _ExamplePrompt(
                  'Ein Zahlen-Lernspiel für mein 7-jähriges Kind: Tiere zählen, '
                  'das richtige Ergebnis antippen, mit Sternen als Belohnung.',
                ),
              ],
            ),
            _Section(
              icon: Icons.bolt,
              title: 'Größe und Credits',
              children: [
                _Bullets([
                  'Klein – 1 Credit: ein Spielprinzip, z. B. Tetris, Snake, Quiz.',
                  'Mittel – 2 Credits: mehrere Level, Menü und Effekte.',
                  'Groß – 5 Credits: umfangreich, z. B. ein 3D-Rennspiel mit '
                      'mehreren Strecken – gebaut vom stärksten KI-Modell (Gemini Pro).',
                  'Weiterbauen kostet 1 bis 3 Credits, je nachdem wie groß das '
                      'Spiel schon ist.',
                  'Vorlagen-Links kosten 1 Credit extra.',
                  'Schlägt eine Erstellung fehl, bekommst du die Credits '
                      'automatisch zurück.',
                  'Mit eigenem API-Key fallen keine Credits an.',
                ]),
              ],
            ),
            _Section(
              icon: Icons.auto_fix_high,
              title: 'Weiterbauen',
              children: [
                _Bullets([
                  'Öffne ein Spiel und tippe auf ✨ „Weiterbauen“ – oder direkt '
                      'in der Projektliste.',
                  'Beschreibe, was neu oder anders sein soll, z. B. jeden Tag '
                      'ein neues Level.',
                  'So kann ein Spiel über Tage und Wochen wachsen. Jede Änderung '
                      'wird als Version gespeichert.',
                  'Sehr große Spiele (über ca. 250 KB Code) lassen sich nicht '
                      'mehr weiterbauen – dann lieber ein neues Projekt starten.',
                ]),
              ],
            ),
            _Section(
              icon: Icons.list_alt,
              title: 'Projekte, Medien-Ordner und Verknüpfungen',
              children: [
                _Bullets([
                  'Tippe in der Liste auf ein Projekt: Starten, Weiterbauen, '
                      'Medien-Ordner, Teilen, Verknüpfung, Größe oder Löschen.',
                  'Im Medien-Ordner liegen Bilder, Sounds und 3D-Modelle des Spiels. '
                      'Füge Fotos, Dateien vom Handy (z. B. .ogg, .mp3, .glb oder '
                      'ZIP-Pakete) oder Dateien aus den Quellen hinzu.',
                  'Neue Dateien nutzt das Spiel, sobald du es weiterbaust – z. B. mit '
                      '„Nutze den Sound engine als Motorgeräusch“.',
                  '„Verknüpfung auf dem Startbildschirm“ legt ein eigenes Icon an, das '
                      'das Spiel direkt startet.',
                  'Teilen schickt das Spiel als .html-Datei – sie läuft beim '
                      'Empfänger im Browser, auch ohne PromptPlay.',
                  'Einstellungen → „Backup speichern“ sichert alle Spiele in einer '
                      'Datei. Nach einer Neuinstallation holst du sie mit „Backup '
                      'einspielen“ zurück.',
                ]),
              ],
            ),
            _Section(
              icon: Icons.image_outlined,
              title: 'Eigene Grafiken',
              children: [
                _Bullets([
                  'Füge beim Erstellen bis zu 6 Bilder hinzu, z. B. Huhn, '
                      'Hintergrund und Fadenkreuz, und gib ihnen kurze Namen.',
                  'Beschreibe im Wunsch, wofür sie gedacht sind: „huhn ist das '
                      'Ziel, wolken ist der Hintergrund“.',
                  'Die Bilder stecken danach im Spiel – auch offline und beim '
                      'Teilen.',
                  'Eigene Grafiken funktionieren nur mit Gemini (PromptPlay '
                      'Cloud oder eigener Gemini-Key), nicht mit Groq.',
                  'Verwende nur Bilder, an denen du die Rechte hast.',
                ]),
              ],
            ),
            _Section(
              icon: Icons.key_outlined,
              title: 'Credits oder eigener API-Key?',
              children: [
                _Bullets([
                  'Ohne Key nutzt du PromptPlay Cloud mit Credits. Nach der '
                      'Anmeldung mit Google gibt es einmalig 2 Gratis-Credits, '
                      'weitere im Shop.',
                  'Mit eigenem kostenlosen Key von Gemini oder Groq erstellst du '
                      'unbegrenzt – Einstellungen → „Key holen“.',
                  'Groq ist sehr schnell, eignet sich aber nur für kleinere '
                      'Spiele, kann keine eigenen Fotos ansehen und keine Seiten '
                      'lesen. Übernommene 3D-Modelle funktionieren aber.',
                ]),
              ],
            ),
            _Section(
              icon: Icons.build_outlined,
              title: 'Wenn etwas nicht klappt',
              children: [
                _Bullets([
                  'Spiel hat einen Fehler: „Weiterbauen“ und den Fehler '
                      'beschreiben.',
                  'Neue Version gefällt nicht: ⋮ → „Versionen“ und eine frühere '
                      'wiederherstellen.',
                  'Unangemessener Inhalt: ⋮ → „Inhalt melden“.',
                  'Credits gibt es nur mit Google-Anmeldung (Einstellungen → '
                      'Konto) – so gehen sie auch bei Handywechsel nie verloren.',
                ]),
              ],
            ),
            _Section(
              icon: Icons.block,
              title: 'Was (noch) nicht geht',
              children: [
                _Bullets([
                  'Online-Mehrspieler oder Spielstände auf mehreren Geräten.',
                  'Spiele, die zur Laufzeit Inhalte aus dem Internet laden – '
                      'alles läuft offline im Spiel.',
                  'Sounds per KI erzeugen klingt einfacher als echte Aufnahmen – für '
                      'beste Ergebnisse Sounds aus den Quellen (z. B. Kenney) nutzen.',
                  'Aufwendige 3D-Spiele in Konsolenqualität.',
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text),
      );
}

class _Steps extends StatelessWidget {
  const _Steps(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(steps[i])),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.items);

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  '),
                Expanded(child: Text(item)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Beispiel-Wunsch mit „Übernehmen“-Button.
class _ExamplePrompt extends StatelessWidget {
  const _ExamplePrompt(this.prompt);

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('„$prompt“', style: theme.textTheme.bodyMedium),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(prompt),
                icon: const Icon(Icons.edit_note),
                label: const Text('Übernehmen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
