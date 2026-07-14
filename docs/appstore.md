# App-Store-Vorbereitung — Voebbar

Arbeitsdokument für die Einreichung. Texte können direkt in App Store Connect übernommen werden.

## Eckdaten

| Feld | Wert |
|---|---|
| App-Name | **Voebbar** |
| Untertitel (Claim) | Bibo Berlin |
| Bundle-ID | `de.voebb.menubar.ios` |
| Primäre Kategorie | Dienstprogramme (Utilities) |
| Sekundäre Kategorie | Bücher (Books) |
| Altersfreigabe | 4+ |
| Preis | Kostenlos |
| Support-URL | https://github.com/noestreich/voebbar |
| Datenschutz-URL | https://github.com/noestreich/voebbar/blob/main/PRIVACY.md |
| Export Compliance | `ITSAppUsesNonExemptEncryption = NO` (im Info.plist gesetzt — keine Nachfrage beim Upload) |

## App-Privacy-Angaben (Nutrition Label)

**„Daten werden nicht erhoben"** — die App hat keine Server, kein Tracking, keine Analytics.
Alle Daten bleiben auf dem Gerät (UserDefaults + Keychain).

## Beschreibung (Entwurf)

> Voebbar zeigt dir die Ausleihen deiner Berliner Bibliothekskonten (VÖBB) auf einen Blick —
> für beliebig viele Bibliotheksausweise.
>
> • Alle ausgeliehenen Medien mit Rückgabedatum, sortiert nach Fälligkeit
> • Ampel-System: rot = bald fällig, orange = demnächst, grün = entspannt
> • Medien verlängern direkt aus der App — geprüft wird vorher, was überhaupt verlängerbar ist
> • Mehrere Konten (z.B. die ganze Familie), ein- und ausklappbar
> • Erinnerung vor dem nächsten Rückgabedatum (1 Tag / 3 Tage / 1 Woche vorher)
> • Gebühren im Blick
> • Ausweisnummer bequem per Barcode-Scan von der Kartenrückseite übernehmen
> • Zuletzt geladener Stand sofort beim Öffnen sichtbar, Aktualisierung läuft im Hintergrund
>
> Deine Daten gehören dir: Passwörter liegen ausschließlich im Schlüsselbund deines iPhones,
> es gibt keine Server, kein Tracking, keine Werbung.
>
> Hinweis: Voebbar ist ein privates, inoffizielles Projekt ohne Verbindung zum VÖBB oder zur
> ZLB. Die App greift auf die offizielle Webseite voebb.de zu — ist diese wegen
> Wartungsarbeiten nicht erreichbar, funktioniert auch die App nicht. Du benötigst einen
> gültigen Bibliotheksausweis des Verbunds der Öffentlichen Bibliotheken Berlins.

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

> Voebbar is an unofficial, private client for the Berlin public library network (VÖBB).
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

- [ ] App-Store-Connect: App anlegen (Name „Voebbar", Bundle-ID `de.voebb.menubar.ios`)
- [ ] Untertitel „Bibo Berlin" eintragen
- [ ] Beschreibung + Keywords aus diesem Dokument übernehmen
- [ ] Datenschutz-Label „Daten werden nicht erhoben" ausfüllen
- [ ] Datenschutz-URL + Support-URL eintragen
- [ ] Screenshots aufnehmen und hochladen
- [ ] Demo-Konto in App-Review-Informationen hinterlegen
- [ ] In Xcode: Product → Archive → Distribute App → App Store Connect
- [ ] TestFlight-Runde mit Familie (optional, empfohlen)
- [ ] Zur Prüfung einreichen
