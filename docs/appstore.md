# App-Store-Vorbereitung — VÖPP

Arbeitsdokument für die Einreichung. Texte können direkt in App Store Connect übernommen werden.

## Eckdaten

| Feld | Wert |
|---|---|
| App-Name | **VÖPP** |
| Untertitel (Claim) | Die App für dein VÖBB-Konto (Vorschlag ab 1.9.3: „Ausleihen, Verlängern, Verlauf – iPhone und Mac“) |
| Bundle-ID | `de.ncls.voebbar` |
| Primäre Kategorie | Dienstprogramme (Utilities) |
| Sekundäre Kategorie | Bücher (Books) |
| Altersfreigabe | 4+ |
| Preis | Kostenlos |
| Marketing-URL | https://voepp.de |
| Support-URL | https://github.com/noestreich/voebbar |
| Datenschutz-URL | https://github.com/noestreich/voebbar/blob/main/PRIVACY.md |
| Export Compliance | `ITSAppUsesNonExemptEncryption = NO` (im Info.plist gesetzt — keine Nachfrage beim Upload) |

## App-Privacy-Angaben (Nutrition Label)

**„Daten werden nicht erhoben"** — die App hat keine Server, kein Tracking, keine Analytics.
Alle Daten bleiben auf dem Gerät (UserDefaults + Keychain).

## Beschreibung (Stand 1.9.3, iOS und Mac identisch)

> VÖPP zeigt dir die Ausleihen deiner Berliner Bibliothekskonten (VÖBB) auf einen Blick – für beliebig viele Bibliotheksausweise, auf iPhone und Mac. Ein Download für beide Geräte.
>
> AUSLEIHEN IM BLICK
> • Alle ausgeliehenen Medien mit Rückgabedatum, sortiert nach Fälligkeit
> • Ampel-System: rot = bald fällig, orange = demnächst, grün = entspannt
> • Mehrere Konten, etwa die ganze Familie, ein- und ausklappbar
> • Pro Konto Gebühren, Abholcode und Hinweis, wenn der Ausweis bald abläuft
> • Bereitstellungen: Bestellte Medien, die zur Abholung bereitliegen, mit Abholfrist
> • Kurze Bibliotheksnamen, damit die Liste ruhig bleibt
>
> VERLÄNGERN
> • Einzelne Medien oder alle verlängerbaren eines Kontos direkt aus der App
> • Vorher wird geprüft, was VÖBB überhaupt verlängern lässt – gesperrte Medien bleiben außen vor, der Grund steht in der Detailansicht
> • Als verlängert gilt nur, was VÖBB danach mit neuem Datum bestätigt
>
> VERLAUF
> • Welche Medien du wann ausgeliehen und zurückgegeben hast, nach Monat gruppiert, mit Suche und Kontofilter
> • Als Text teilbar, etwa für Nachrichten oder Notizen
> • Entsteht nur auf deinem Gerät und lässt sich abschalten
>
> ERINNERN
> • Mitteilung vor dem nächsten Rückgabedatum: 1 Tag, 3 Tage oder 1 Woche vorher
>
> AUF DEM MAC
> • Fenster-App plus Symbol in der Menüleiste mit den Resttagen des dringlichsten Mediums
> • Das Menü fasst jedes Konto in einer Zeile zusammen und aktualisiert stündlich im Hintergrund
>
> KOMFORT
> • Zuletzt geladener Stand sofort beim Öffnen, Aktualisierung läuft im Hintergrund
> • Ausweisnummer per Barcode-Scan von der Kartenrückseite (iPhone)
> • Oberfläche in Deutsch, Englisch, Türkisch, Polnisch und Russisch
>
> DATENSCHUTZ
> Passwörter liegen ausschließlich im Schlüsselbund deines Geräts. Alle weiteren Daten bleiben lokal. Keine Server, kein Tracking, keine Werbung.
>
> HINWEIS
> VÖPP ist ein privates, inoffizielles Projekt ohne Verbindung zum VÖBB oder zur ZLB. Die App greift auf die offizielle Webseite voebb.de zu. Ist diese etwa wegen Wartungsarbeiten nicht erreichbar, funktioniert auch die App nicht. Du benötigst einen gültigen Bibliotheksausweis des Verbunds der Öffentlichen Bibliotheken Berlins. Titel und Statusmeldungen stammen von VÖBB und erscheinen so, wie die Bibliothek sie liefert.

## Keywords (max. 100 Zeichen)

```
Bibliothek,Berlin,VÖBB,Bücherei,Ausleihe,verlängern,Rückgabe,ZLB,Bücher,Bibo
```

## App-Review-Informationen

**Demo-Zugang (PFLICHT — vor Einreichung eintragen, niemals ins Repo committen!):**

```
Ausweisnummer: <hier eintragen>
Passwort:      <hier eintragen>
```

**Notizen für das Review-Team (Entwurf):**

> VÖPP is an unofficial, private client for the Berlin public library network (VÖBB).
> It signs in to the official website voebb.de with the user's own library-card credentials
> and shows current loans, due dates and fees, and can renew loans. All data stays on the
> device (Keychain/UserDefaults); the app has no backend, no analytics and no ads.
> A valid Berlin library card is required — please use the demo account above.
> The barcode scanner (camera) is only used to fill in the card number field.

## Screenshots

Benötigt: mindestens ein Satz für 6,9" (iPhone 16 Pro Max) **oder** 6,7"/6,5" — direkt auf dem
Gerät aufnehmen (Seitentaste + Lauter). Empfohlene Motive:

1. Hauptliste mit zwei Konten, gemischten Ampelfarben und Statuszeile
2. Verlängern-Ergebnis (Popup)
3. Konten-Verwaltung mit Benachrichtigungs-Einstellung
4. Barcode-Scanner
5. Formular mit Auge-Knopf

## Checkliste bis zur Einreichung

- [ ] App-Store-Connect: App anlegen (Name „VÖPP", Bundle-ID `de.ncls.voebbar`)
- [ ] Untertitel „Die App für dein VÖBB-Konto" eintragen
- [ ] Beschreibung + Keywords aus diesem Dokument übernehmen
- [ ] Datenschutz-Label „Daten werden nicht erhoben" ausfüllen
- [ ] Datenschutz-URL + Support-URL eintragen
- [ ] Screenshots aufnehmen und hochladen
- [ ] Demo-Konto in App-Review-Informationen hinterlegen
- [ ] In Xcode: Product → Archive → Distribute App → App Store Connect
- [ ] TestFlight-Runde mit Familie (optional, empfohlen)
- [ ] Zur Prüfung einreichen
