# voebbar

Ausleihen, Fälligkeiten und Gebühren mehrerer Bibliothekskarten des
**[VÖBB](https://www.voebb.de/)** (Verbund der Öffentlichen Bibliotheken Berlins) – mit
Verlängerung auf Knopfdruck. Zwei Apps, ein gemeinsamer Kern (`VOEBBKit`):

- **macOS-Menüleisten-App** (AppKit, Swift Package Manager, macOS 13+)
- **iOS-App „Voebbar"** (SwiftUI, iOS 16+, `iOS/VOEBBApp.xcodeproj`)

![VÖBB Bibliothek](assets/bibo-1.jpg)

## Funktionen

**Menüleiste & Übersicht**
- Anzahl aller ausgeliehenen Medien als Badge im Menüleisten-Symbol
- Dringlichkeitsindikator: Symbol wechselt, wenn ein Medium in weniger als 7 Tagen fällig ist
- Pro Konto: Anzahl Ausleihen, nächste Fälligkeit (farbcodiert nach Dringlichkeit), offene Gebühren
- Sortierbares Gesamtfenster über alle Konten mit Emoji-Ampel (📕 < 7 Tage · 📙 7–14 Tage · 📗 > 14 Tage)
- Tooltips mit vollständigen Titeln und Bibliotheksnamen; Titel in der Menüleiste werden sinnvoll gekürzt

**Verlängern**
- „Alle verlängern"-Knopf pro Konto
- Zwei-Schritt-Verlängerung: erst Verlängerbarkeit prüfen, dann nur verlängerbare Medien einreichen —
  verhindert, dass VÖBB die ganze Aktion abbricht, sobald ein Titel gesperrt ist

**Mehrere Konten**
- Unbegrenzt viele Bibliothekskarten, jede mit eigenem Namen
- Passwörter liegen ausschließlich im macOS-Schlüsselbund, nie im Klartext

**Automatisches Refresh**
- Konfigurierbares Intervall (Standard: 4 Stunden)
- Stale-Prüfung beim Öffnen des Menüs

## iOS-App „Voebbar"

Die iOS-App bringt die Ausleihen aufs iPhone: Liste aller Medien gruppiert nach Konto
(ein-/ausklappbar), Ampelfarben nach Fälligkeit, Verlängern pro Konto, Erinnerung vor dem
nächsten Rückgabedatum (konfigurierbar), Barcode-Scan der Ausweisnummer per Kamera und
Offline-Anzeige des letzten Stands mit Hintergrund-Aktualisierung.

```sh
open iOS/VOEBBApp.xcodeproj   # in Xcode öffnen, iPhone wählen, Run
```

Alle Daten bleiben auf dem Gerät — Details in der [Datenschutzerklärung](PRIVACY.md).

## Bauen & starten (macOS)

```sh
./build_app.sh   # erzeugt VOEBBMenu.app
open VOEBBMenu.app
```

Läuft als Accessory-App (`LSUIElement`, kein Dock-Icon). Xcode wird für die Mac-App nicht
benötigt — nur die Xcode-Kommandozeilen-Tools (`xcode-select --install`).

## Erste Schritte

1. App starten — beim ersten Start öffnet sich automatisch das Einstellungsfenster
2. Bibliothekskarte hinzufügen: Name, Ausweisnummer und Passwort eintragen
3. Das Menüleisten-Symbol zeigt sofort die Ausleihen aller eingetragenen Konten

## Architektur

Reines HTML-Scraping der aDIS-Weboberfläche (`VOEBBService` / `HTMLParser`), kein öffentliches
API — gekoppelt an VÖBBs aktuelles Markup. `StatusBarController` steuert Statusitem, Menü und
Refresh-Timer. Siehe `CLAUDE.md` für Details.

## Anforderungen

- macOS 13 Ventura oder neuer
- Xcode-Kommandozeilen-Tools
- Ein aktiver VÖBB-Bibliotheksausweis
