# PromptPlay im Google Play Store veröffentlichen

Diese Datei enthält alles, was du in der [Play Console](https://play.google.com/console) eintragen musst, und den Stand der technischen Anforderungen.

## 1. Vor dem Einreichen erledigen

- [x] **Datenschutzerklärung ausfüllen** (Verantwortlicher eingetragen).
- [ ] **Screenshots machen:** mindestens 2 Handy-Screenshots, z. B. Projektliste, Erstellen-Bildschirm, laufendes Spiel.
- [ ] **Upload-Schlüssel sichern:** `android/app/upload-keystore.jks` sowie Alias und Passwort aus `android/key.properties` an zwei getrennten Orten sichern, z. B. Datei im Cloud-Speicher und Passwort im Passwort-Manager. Beides ist absichtlich nicht im Repository.

## 2. Technische Anforderungen (Stand: Version 1.2.0)

| Anforderung | Stand |
|---|---|
| App Bundle (`.aab`) | `build/app/outputs/bundle/release/app-release.aab` |
| Signatur mit eigenem Upload-Schlüssel | ✅ |
| Target API Level 36 (Pflicht seit 31.08.2026) | ✅ targetSdk 36, minSdk 24 |
| 16-KB-Seitengröße | ✅ alle nativen Bibliotheken auf ≥ 16 KB ausgerichtet |
| Meldefunktion für KI-generierte Inhalte | ✅ Player → ⋮ → „Inhalt melden“ |
| Datenschutzerklärung in App und Store | ✅ Einstellungen → „Datenschutzerklärung“ |
| Konto- und Datenlöschung in der App | ✅ Einstellungen → „Cloud-Konto & Credits löschen“ |
| Keine Werbung, kein Tracking | ✅ |
| Käufe nur über Google Play Billing | ✅ Credit-Shop mit `credits_10`, `credits_30`, `credits_70`, Prüfung auf dem Server |
| Bildauswahl ohne Speicher-Berechtigung | ✅ Android-Fotoauswahl (keine Berechtigung für alle Fotos nötig) |
| Berechtigungen | nur normale Berechtigungen (Internet, Google Play Billing; Firebase ergänzt Netzwerkstatus, Wake-Lock, Cloud Messaging) |

## 3. App anlegen

- **App-Name (max. 30 Zeichen):** `PromptPlay: Vibe Coding Games`
  „Gemini“ ist eine Marke von Google und gehört deshalb nicht in den Namen.
- **Standardsprache:** Deutsch
- **App oder Spiel:** App
- **Kostenlos oder kostenpflichtig:** Kostenlos (mit In-App-Käufen)

## 4. Store-Eintrag

**Kurzbeschreibung (max. 80 Zeichen):**

> Beschreibe deine Idee – die KI baut dir daraus ein Spiel oder eine Mini-App.

**Vollständige Beschreibung:**

> Vibe Coding für dein Handy: PromptPlay verwandelt deine Ideen in spielbare Mini-Apps – ganz ohne Programmierkenntnisse. Beschreibe einfach, was du möchtest – zum Beispiel „Baue mir ein Tetris für Touchscreens“ oder „Erstelle mir ein Rennspiel“ – und die KI erstellt daraus in Sekunden eine fertige App, die du sofort im Vollbild spielen kannst.
>
> ★ So funktioniert's
> • Idee eingeben oder ein Beispiel antippen
> • „Erstellen“ tippen – die KI schreibt die komplette App
> • Sofort spielen, später erneut öffnen oder mit Freunden teilen
>
> ★ Funktionen
> • Spiele, Quiz, Timer und vieles mehr – optimiert für Touchscreens
> • Vollbild-Modus für ungestörtes Spielen
> • Alle Projekte übersichtlich in deiner Bibliothek
> • Teilen des HTML-Codes über den Android-Teilen-Dialog
> • 2 Gratis-Credits nach Anmeldung mit Google
> • Weitere Credits im Shop: 10 Credits für 1,99 €, 30 für 4,99 €, 70 für 9,99 €
> • Größe wählen: Klein, Mittel oder Groß
> • Weiterbauen: Spiele über Tage und Wochen erweitern, mit Versionen zum Zurückgehen
> • Eigene Grafiken: deine Bilder als Spielfiguren oder Hintergrund
> • 3D-Spiele: Three.js ist eingebaut – z. B. Autorennen mit Kamera hinter dem Auto
> • Echte 3D-Modelle und Sounds: Gratis-Quellen wie Kenney und Poly Haven direkt in der App durchsuchen und ins Spiel übernehmen
> • Referenzbilder: Die KI orientiert sich am Stil eines Bildes, ohne es zu kopieren
> • Medien-Ordner pro Spiel und Verknüpfungen auf dem Startbildschirm
> • Hilfe mit Schritt-für-Schritt-Beispielen
> • Oder unbegrenzt erstellen mit einem eigenen kostenlosen API-Key von Google Gemini oder Groq
>
> ★ Für Familien
> • Familien-Modus: Erstelle als Elternteil kindgerechte Spiele für deine Kinder – ohne Gewalt, ohne Gruseliges, mit einfacher Sprache und den strengsten Sicherheitsfiltern
> • Kindgerechte Spiele bleiben es auch beim Weiterbauen
> • Tipp: Schau dir jedes Spiel kurz selbst an, bevor du es deinem Kind gibst
>
> ★ Datenschutz
> • Keine Werbung, kein Tracking
> • Projekte und API-Keys bleiben auf deinem Gerät
> • Konto und Daten jederzeit in der App löschbar
>
> Hinweis: Die Inhalte werden von einer KI erzeugt und können Fehler enthalten. Unangemessene Inhalte meldest du direkt in der App über „Inhalt melden“.

**Grafiken:**

| Feld | Datei |
|---|---|
| App-Symbol 512 × 512 | [store/icon-512.png](store/icon-512.png) |
| Feature-Grafik 1024 × 500 | [store/feature-graphic-1024x500.png](store/feature-graphic-1024x500.png) |
| Handy-Screenshots (mind. 2) | selbst aufnehmen |

**Kategorie:** Unterhaltung · **E-Mail:** deine Entwickler-Adresse · **Website:** https://siriussagittarius.github.io/gemini-play/

## 5. App-Inhalte (Richtlinien-Formulare)

- **Datenschutzerklärung:** `https://siriussagittarius.github.io/gemini-play/datenschutz.html`
- **Werbung:** Nein
- **Anmeldedaten (früher „App-Zugriff“):** „Ja“ → Anleitung ohne Nutzername/Passwort, Text:
  `No login is needed to open the app. To create games, sign in with Google (Einstellungen > Konto): each Google account receives 2 free credits once. Credit purchases are optional.`
- **Zielgruppe:** 18 Jahre und älter, auch mit Familien-Modus. Die App richtet sich an **Eltern**, die Spiele für ihre Kinder erstellen, nicht an Kinder selbst. Würde Google sie als Kinder-App einstufen, gälten die strengen Familien-Richtlinien, die eine KI-App mit Käufen kaum erfüllen kann. Deshalb im Store-Eintrag (Texte, Screenshots, Grafiken) **Erwachsene ansprechen** und keine Kinderfiguren oder Kinder-Ansprache („Hey Kids!“) verwenden.
- **Einstufung (IARC-Fragebogen):** Die App selbst enthält keine Gewalt, Sexualität oder Glücksspiel. Wenn gefragt wird, ob Nutzer Inhalte erzeugen oder KI-Inhalte generiert werden: **Ja**. Nutzer können **nicht** miteinander kommunizieren, und es gibt **keine** Standortfreigabe. **Digitale Käufe: Ja.**
- **Finanzfunktionen, Gesundheit, Behörden-App, Nachrichten-App:** Nein

### Datensicherheit

| Frage | Antwort |
|---|---|
| Werden Nutzerdaten erhoben oder geteilt? | Ja |
| Werden alle Daten bei der Übertragung verschlüsselt? | Ja |
| Können Nutzer die Löschung ihrer Daten beantragen? | Ja – Link: `https://siriussagittarius.github.io/gemini-play/datenschutz.html#loeschung` |

| Datentyp | Erhoben | Geteilt | Optional | Zweck |
|---|---|---|---|---|
| Personenbezogene Daten → Nutzer-IDs (anonyme Firebase-Kennung) | Ja | Nein | Nein | App-Funktionalität; Betrugsprävention, Sicherheit |
| Finanzdaten → Kaufverlauf (gekaufte Credit-Pakete) | Ja | Nein | Ja | App-Funktionalität |
| Personenbezogene Daten → E-Mail-Adresse, Name (nur bei Google-Anmeldung) | Ja | Nein | Ja | App-Funktionalität, Kontoverwaltung |
| Fotos und Videos → Fotos (eigene Grafiken; nur zur Generierung übertragen, nicht gespeichert) | Ja | Nein | Ja | App-Funktionalität |
| App-Aktivitäten → Andere nutzergenerierte Inhalte (Prompts, Meldungen) | Ja | Nein | Nein | App-Funktionalität |
| Geräte- oder andere IDs (von Firebase-SDKs) | Ja | Nein | Nein | App-Funktionalität |

Google (Firebase, Gemini API, Google Play) handelt als Dienstleister. Das gilt nach Play-Definition nicht als „Teilen“. Gleiche die Angaben zu den Firebase-SDKs mit Googles Übersicht ab: [Firebase-Angaben für die Datensicherheit](https://firebase.google.com/docs/android/play-data-disclosure).

## 6. Hochladen und veröffentlichen

1. **Testen → Geschlossener Test:** einen Track anlegen und `app-release.aab` hochladen.
   - Play App Signing ist bei neuen Apps Standard. Google signiert die ausgelieferte App mit eigenem Schlüssel; dein Upload-Schlüssel dient nur zum Hochladen.
2. **Tester einladen.** Für neue private Entwicklerkonten gilt: Mindestens 12 Tester müssen 14 Tage am geschlossenen Test teilnehmen. Erst danach kannst du die Produktion beantragen.
3. Nach der Freigabe: **Produktion → Neuer Release** mit demselben App Bundle.

## 7. Credit-Verkauf einrichten

Die App bietet im Shop drei Pakete an. Die Cloud Function `verifyPurchase` prüft jeden Kauf bei Google Play, schreibt die Credits genau einmal gut und verbraucht den Kauf danach, damit er erneut gekauft werden kann. Damit das funktioniert:

1. **Zahlungsprofil anlegen:** Play Console → Einrichtung → Zahlungsprofil (Bankverbindung, Adresse).
2. **Version mit Kauf-Funktion hochladen** (ab 1.1.0, siehe Abschnitt 6). Erst dann lassen sich In-App-Produkte anlegen.
3. **Produkte anlegen:** App → Monetarisieren → Produkte → In-App-Produkte (Einmalkäufe) → „Produkt erstellen“. Die IDs genau so übernehmen, sie sind später nicht mehr änderbar. Jedes Produkt speichern und **aktivieren**.

   | Produkt-ID | Name | Beschreibung | Preis |
   |---|---|---|---|
   | `credits_10` | 10 Credits | 10 Credits für neue Spiele und Mini-Apps | 1,99 € |
   | `credits_30` | 30 Credits | 30 Credits für neue Spiele und Mini-Apps | 4,99 € |
   | `credits_70` | 70 Credits | 70 Credits für neue Spiele und Mini-Apps | 9,99 € |
4. **Google Play Android Developer API aktivieren:** Google Cloud Console des Firebase-Projekts → APIs & Dienste → Bibliothek → „Google Play Android Developer API“ → Aktivieren.
5. **Server berechtigen:** Play Console → Nutzer und Berechtigungen → „Neue Nutzer einladen“ → E-Mail des Dienstkontos der Functions eintragen (Google Cloud Console → IAM → Dienstkonten → „Default compute service account“, endet auf `-compute@developer.gserviceaccount.com`) → bei der App die Berechtigungen **„Finanzdaten ansehen“** und **„Bestellungen und Abos verwalten“** vergeben.
6. **Lizenztester eintragen:** Play Console → Einstellungen → Lizenztests → deine Test-E-Mail-Adressen. Diese Konten kaufen im Test, ohne belastet zu werden.
7. **Vor echten Verkäufen:**
   - **Gemini-Key mit Abrechnung** auf dem Server hinterlegen (`functions:secrets:set GEMINI_API_KEY`). Die kostenlose Stufe reicht für zahlende Nutzer nicht.
   - **Kosten im Blick behalten:** Nach Mehrwertsteuer und 15 % Google-Gebühr bleiben pro Credit ca. 14 ct (10er), 12 ct (30er) bzw. 10 ct (70er). Ein einfaches Spiel kostet bei Gemini 3.8 Flash ca. 3 ct, ab 2027 ca. 6 ct.
   - **App Check aktivieren** (siehe Abschnitt 9).
   - **Rechtliches:** Credit-Verkauf ist eine gewerbliche Tätigkeit (Gewerbeanmeldung, Impressum, Steuer). Das kläre bitte mit Finanzamt oder Steuerberater.

## 8. Google-Anmeldung einrichten

1. Firebase-Konsole → Authentication → Anmeldemethode → „Neuen Anbieter hinzufügen“ → **Google** aktivieren.
2. Die SHA-1-Fingerabdrücke von Upload- und Debug-Schlüssel sind in der Firebase-App hinterlegt. Nach dem ersten Upload kommt der **SHA-1 des App-Signaturschlüssels** aus der Play Console dazu (Firebase → Projekteinstellungen → Android-App → Fingerabdruck hinzufügen).
3. Die Web-Client-ID aus der Firebase-Konfiguration in `lib/firebase_options.dart` als `kGoogleWebClientId` eintragen und die App neu bauen.

## 9. Nach dem ersten Upload

- **SHA-1 des App-Signaturschlüssels** (Play Console → Einrichtung → App-Signatur) zusätzlich bei der Einschränkung des Firebase-API-Keys eintragen, sonst funktioniert die Cloud in der Store-Version nicht.
- **Firebase App Check (Play Integrity) aktivieren** und in `functions/index.js` `enforceAppCheck: true` setzen. So kann nur deine echte App die Credits nutzen. Spätestens vor dem ersten echten Verkauf.

## 10. Neue Version veröffentlichen

1. In `pubspec.yaml` die Version erhöhen, z. B. `1.2.1+4`. Die Zahl hinter `+` muss bei jedem Upload steigen.
2. `flutter build appbundle --release`
3. In der Play Console einen neuen Release mit dem neuen Bundle anlegen.
