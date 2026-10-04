# PromptPlay im Google Play Store veröffentlichen

Diese Datei enthält alles, was du in der [Play Console](https://play.google.com/console) eintragen musst, und den Stand der technischen Anforderungen.

## 1. Vor dem Einreichen erledigen

- [ ] **Datenschutzerklärung ausfüllen:** In [docs/datenschutz.html](docs/datenschutz.html) die gelb markierten Felder (Name, Anschrift, E-Mail) ersetzen und pushen. Ohne Verantwortlichen ist sie nach DSGVO unvollständig.
- [ ] **Screenshots machen:** mindestens 2 Handy-Screenshots, z. B. Projektliste, Erstellen-Bildschirm, laufendes Spiel.
- [ ] **Upload-Schlüssel sichern:** `android/app/upload-keystore.jks` und das Passwort aus `android/key.properties` an zwei getrennten Orten sichern, z. B. Datei im Cloud-Speicher und Passwort im Passwort-Manager. Beides ist absichtlich nicht im Repository.

## 2. Technische Anforderungen (Stand: Version 1.0.0)

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
| Keine Zahlungen außerhalb von Google Play | ✅ „Credits nachkaufen“ zeigt nur „in Vorbereitung“ |
| Berechtigungen | nur normale Berechtigungen (Internet; Firebase ergänzt Netzwerkstatus, Wake-Lock, Cloud Messaging) |

## 3. App anlegen

- **App-Name (max. 30 Zeichen):** `PromptPlay – KI-Spiele & Apps`
  „Gemini“ ist eine Marke von Google und gehört deshalb nicht in den Namen.
- **Standardsprache:** Deutsch
- **App oder Spiel:** App
- **Kostenlos oder kostenpflichtig:** Kostenlos

## 4. Store-Eintrag

**Kurzbeschreibung (max. 80 Zeichen):**

> Beschreibe deine Idee – die KI baut dir daraus ein Spiel oder eine Mini-App.

**Vollständige Beschreibung:**

> PromptPlay verwandelt deine Ideen in spielbare Mini-Apps. Beschreibe einfach, was du möchtest – zum Beispiel „Baue mir ein Tetris für Touchscreens“ oder „Erstelle ein Quiz mit 10 Fragen über das Sonnensystem“ – und die KI erstellt daraus in Sekunden eine fertige App, die du sofort im Vollbild spielen kannst.
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
> • 3 Gratis-Credits zum Ausprobieren – ohne Registrierung
> • Unbegrenzt erstellen mit einem eigenen kostenlosen API-Key von Google Gemini oder Groq
>
> ★ Datenschutz
> • Keine Werbung, kein Tracking
> • Projekte und API-Keys bleiben auf deinem Gerät
> • Anonymes Konto, jederzeit in der App löschbar
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
- **App-Zugriff:** Alle Funktionen ohne besondere Zugangsdaten verfügbar
- **Zielgruppe:** 18 Jahre und älter. KI-Inhalte sind nicht vorhersagbar; so gelten die Zusatzregeln für Kinder-Apps nicht.
- **Einstufung (IARC-Fragebogen):** Die App selbst enthält keine Gewalt, Sexualität oder Glücksspiel. Wenn gefragt wird, ob Nutzer Inhalte erzeugen oder KI-Inhalte generiert werden: **Ja**. Nutzer können **nicht** miteinander kommunizieren, und es gibt **keine** Standortfreigabe und **keine** Käufe.
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
| App-Aktivitäten → Andere nutzergenerierte Inhalte (Prompts, Meldungen) | Ja | Nein | Nein | App-Funktionalität |
| Geräte- oder andere IDs (von Firebase-SDKs) | Ja | Nein | Nein | App-Funktionalität |

Google (Firebase, Gemini API) handelt als Dienstleister. Das gilt nach Play-Definition nicht als „Teilen“. Gleiche die Angaben zu den Firebase-SDKs mit Googles Übersicht ab: [Firebase-Angaben für die Datensicherheit](https://firebase.google.com/docs/android/play-data-disclosure).

## 6. Hochladen und veröffentlichen

1. **Testen → Geschlossener Test:** einen Track anlegen und `app-release.aab` hochladen.
   - Play App Signing ist bei neuen Apps Standard. Google signiert die ausgelieferte App mit eigenem Schlüssel; dein Upload-Schlüssel dient nur zum Hochladen.
2. **Tester einladen.** Für neue private Entwicklerkonten gilt: Mindestens 12 Tester müssen 14 Tage am geschlossenen Test teilnehmen. Erst danach kannst du die Produktion beantragen.
3. Nach der Freigabe: **Produktion → Neuer Release** mit demselben App Bundle.

## 7. Nach dem ersten Upload (empfohlen)

- **SHA-256 des App-Signaturschlüssels kopieren:** Play Console → Einrichtung → App-Signatur.
- **Firebase App Check (Play Integrity) aktivieren.** Dann setzt du in `functions/index.js` `enforceAppCheck: true`. So kann nur deine echte App die Gratis-Credits nutzen.
- **API-Key einschränken:** In der Google Cloud Console den Firebase-API-Key (aus `lib/firebase_options.dart`) auf das Paket `com.promptplay.promptplay` und die SHA-1-Fingerabdrücke beschränken.
- **Gemini-Kontingent:** Der Server-Key nutzt die kostenlose Gemini-Stufe. Ihr Tageslimit ist für viele Nutzer zu klein, und Google darf die Inhalte zur Produktverbesserung verwenden. Für den echten Betrieb einen Key mit aktivierter Abrechnung hinterlegen.

## 8. Neue Version veröffentlichen

1. In `pubspec.yaml` die Version erhöhen, z. B. `1.0.1+2`. Die Zahl hinter `+` muss bei jedem Upload steigen.
2. `flutter build appbundle --release`
3. In der Play Console einen neuen Release mit dem neuen Bundle anlegen.
