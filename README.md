# PromptPlay

<img src="store/icon-512.png" alt="PromptPlay-Icon" width="96" align="right">

KI-Generator für Mini-Apps und Spiele auf Android. Du beschreibst eine Idee, eine KI (Google Gemini oder Groq) schreibt daraus eine eigenständige HTML5-App, und PromptPlay spielt sie im Vollbild ab, speichert sie lokal und teilt sie über den Android-Teilen-Dialog.

## Funktionen

- **Zwei Wege zur Generierung**
  - **Eigener API-Key** für Google Gemini oder Groq: unbegrenzt, direkt vom Gerät aus.
  - **PromptPlay Cloud**: 2 Gratis-Credits nach der Google-Anmeldung (einmalig pro Google-Konto), weitere Credits im Shop (Google Play Billing). Die Generierung läuft über eine Firebase Cloud Function.
- **Größe wählen:** Klein, Mittel, Groß (1, 2 bzw. 3 Credits).
- **Weiterbauen:** Spiele über Tage und Wochen erweitern; jede Änderung wird als Version gespeichert und lässt sich wiederherstellen.
- **Eigene Grafiken:** bis zu 6 Bilder pro Spiel. Das funktioniert nur mit Gemini, nicht mit Groq.
- **Google-Anmeldung**, damit gekaufte Credits erhalten bleiben.
- **Fortschrittsanzeige mit Restzeit** und **Hilfe-Seite** mit Beispielen.
- **Projektliste** mit Öffnen, Weiterbauen, Teilen und Löschen.
- **Player:** WebView mit Touch-Steuerung und Vollbild-Modus.
- **Play-Store-konform:**
  - Inhalte melden
  - Cloud-Konto löschen
  - Datenschutzerklärung
  - targetSdk 36, 16-KB-Seiten

## Aufbau

| Pfad | Inhalt |
|---|---|
| [lib/main.dart](lib/main.dart) | die komplette App |
| `lib/firebase_options.dart` | Firebase-Konfiguration – nicht im Repository, siehe „Firebase einrichten“ |
| [functions/](functions/) | Cloud Functions (Node 22): `ensureUserProfile`, `generateGame`, `verifyPurchase`, `reportContent`, `deleteAccount` |
| [firestore.rules](firestore.rules) | Security Rules: Clients dürfen nur ihr eigenes Credit-Dokument lesen |
| [docs/](docs/) | Startseite und Datenschutzerklärung (GitHub Pages) |
| [store/](store/) | Grafiken für den Play-Store-Eintrag |
| [PLAY_STORE.md](PLAY_STORE.md) | Texte, Formular-Antworten und Schritte für die Veröffentlichung |

## Entwickeln

Voraussetzungen: Flutter (stable), Android SDK, Node.js 22.

```bash
flutter pub get
flutter run
flutter test
```

**Firebase einrichten:** `lib/firebase_options.dart` und `.firebaserc` gehören zu einem bestimmten Firebase-Projekt und sind deshalb nicht im Repository. Erzeuge sie für dein eigenes Projekt mit:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --platforms=android
npx firebase-tools use --add
```

**Cloud Functions:**

```bash
cd functions
npm install
npm run serve    # lokale Emulatoren (Auth, Functions, Firestore)
npm run deploy   # Functions und Firestore-Regeln deployen
```

Der Gemini-Key des Servers liegt im Secret Manager:

```bash
npx firebase-tools functions:secrets:set GEMINI_API_KEY
```

## Release bauen

```bash
flutter build appbundle --release
```

- **Signatur:** Signiert wird mit dem Upload-Schlüssel aus `android/key.properties` und `android/app/upload-keystore.jks`. Beide Dateien sind absichtlich nicht im Repository. Fehlen sie, signiert Gradle mit dem Debug-Schlüssel.
- **[android/gradle.properties](android/gradle.properties)** enthält zwei Einstellungen für den Build:
  - `android.r8.proguardAndroidTxt.disallowed=false`: Nötig, weil `flutter_inappwebview` 1.1.3 noch die alte ProGuard-Datei nutzt, die AGP 9 sonst ablehnt.
  - `kotlin.incremental=false`: Nötig, wenn Pub-Cache und Projekt auf verschiedenen Laufwerken liegen.
