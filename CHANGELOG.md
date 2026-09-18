# Changelog

Versionen von VÖPP (iOS und macOS im App Store, gemeinsame Versionsnummer). Die frühere Menüleisten-App VOEBBMenu (eigene Nummer, zuletzt 1.3) wird seit September 2026 nicht mehr weiterentwickelt.

## Unveröffentlicht

### Darstellung
- **Kurze Bibliotheksnamen:** Statt „Friedrichshain-Kreuzberg: Bezirkszentralbibliothek Pablo Neruda“ steht in Listen jetzt „Pablo Neruda“ — nach einer einheitlichen Kurzliste aller VÖBB-Standorte; nur mehrdeutige Namen tragen den Bezirk („Kurt Tucholsky · Pankow“). Die Detailansicht zeigt weiterhin den vollen Namen.
- **Kürzere Autorzeile:** Nur die erste genannte Person; Übersetzer, Illustratoren und Klammerzusätze entfallen.
- **Bereitstellungen im Raster:** Die Abholfrist steht rechts an der Stelle der Fälligkeitsspalte („bis 01.10.“), die Zeile darunter heißt nur noch „Bereitstellung“.
- **Ruhigere Kontokopfzeilen:** Chevron, Name, Abholcode, Gebühr und Ausleihen-Badge stehen jetzt über alle Konten hinweg in echten Spalten. Die Namensspalte ist so breit wie der längste Kontoname (höchstens ~30 % der Zeile, längere Namen werden gekürzt), der Abholcode steht ohne Klammern in eigener Spalte, die Badge hat eine feste Spalte für drei Ziffern, sodass der Gebührenbetrag nicht mehr springt. Nullwerte sind gedämpft: „–“ statt „0,00 €“, keine Badge bei 0 Ausleihen. Bei großen Schriftgrößen bricht die Kopfzeile einheitlich auf zwei Zeilen um; VoiceOver liest sie als einen Satz mit vollem Namen.

## VÖPP 1.9.1 (iOS + macOS) — 2026-09-16

### Neu
- **Verlauf teilen:** Das Teilen-Symbol im Verlauf gibt die angezeigte Liste als Text weiter — mit Kontofilter und Suche wie in der Ansicht, gegliedert in „Aktuell ausgeliehen“ und Rückgabemonate. Über das Systemmenü an Nachrichten, Mail, Notizen oder als Datei.

## VÖPP 1.9 (iOS + macOS) — 2026-09-14

### Neu
- **VÖPP für den Mac:** Dieselbe App läuft jetzt nativ auf macOS 13+ (Apple Silicon und Intel) — als Fenster-App mit zusätzlichem Menüleisten-Symbol, das die Resttage des dringlichsten Mediums zeigt; das Menü fasst jedes Konto in einer Zeile zusammen (Ampelpunkt, Ausleihen, Gebühren, Bereitstellungen, Ausweis-Hinweis) und öffnet das Fenster. Ein Download für iPhone und Mac; die App aktualisiert sich auf dem Mac stündlich im Hintergrund. Der Barcode-Scanner bleibt iOS-exklusiv.

- **Verlauf:** Ein Uhr-Symbol in der Toolbar öffnet den Ausleih-Verlauf — oben die laufenden Ausleihen, darunter alle zurückgegebenen Medien, nach Monat gruppiert, mit Suche und Kontofilter. VÖBB bietet keine Historie an; VÖPP leitet sie aus den Momentaufnahmen jedes erfolgreichen Abrufs ab (ausgeliehen = neu in der Liste, zurückgegeben = aus der Liste verschwunden). Bewusst monatsgenau („Ausgeliehen September 2026 · zurückgegeben Oktober 2026“). Erfasst wird nur bei einem Abruf der App, ohne aktive Nutzung entsteht kein Verlauf. In den Konten-Einstellungen per „Verlauf sichern“ abschaltbar (Standard: an). Der Verlauf bleibt ausschließlich auf dem Gerät und wird mit dem Konto gelöscht.

### Unter der Haube
- Der Parser behält jetzt die Mediennummer jedes Exemplars (dritte Zeile der Titelzelle) als stabile Identität für den Verlauf.
- Ein Xcode-Target für beide Plattformen; iOS-spezifische Modifier laufen auf macOS als No-ops (`PlatformShims.swift`). Keine funktionalen Änderungen an der iOS-App.

## VÖPP 1.7 (iOS) / VOEBBMenu 1.3 (macOS) — 2026-09-07

### Neu
- **Bereitstellungen:** Abholbereite Bestellungen erscheinen oben in der Liste des jeweiligen Kontos, ausgegraut und ohne Ampelpunkt, mit Ausgabeort und Abholfrist („abholbereit bis …“).

### Zuverlässigkeit
- **Verlängerung wird nur noch bestätigt, wenn sie nachweisbar ist:** Nach dem Verlängern vergleicht die App die Fälligkeitsdaten vorher/nachher pro Titel und Bibliothek. Nur ein späteres Datum gilt als verlängert. Unveränderte Titel werden als „nicht bestätigt“ gemeldet; ist die Antwortseite nicht lesbar, bittet die App um Kontrolle der Ausleihliste. Mehrfach ausgeliehene Exemplare desselben Titels werden dabei korrekt auseinandergehalten.
- **Parserfehler werden nicht mehr als leeres Konto angezeigt:** Meldet die Kontoübersicht N Ausleihen, die Liste liefert aber weniger oder ist nicht erkennbar, gibt es eine Fehlermeldung und die zuletzt bekannten Daten bleiben stehen.
- **Server-Antworten werden strenger geprüft:** HTTP-Fehler (4xx/5xx) und Seiten ohne gültigen Request-Zähler brechen sauber ab, statt eine Fehlerseite als leere Liste zu deuten. Der Request-Zähler wird immer von der aktuellen Seite übernommen.
- **„Fällig in 1 Tag“ stimmt jetzt ganztägig:** Tage bis zur Fälligkeit werden kalendertäglich gezählt (heute = 0, morgen = 1), unabhängig von der Uhrzeit.

### Unter der Haube
- **Ein Login pro Konto statt bis zu drei:** Ausleihen, Verlängerbarkeits-Prüfung und Bereitstellungen laufen in einer VÖBB-Sitzung; der Rücksprung geht wie im Browser über „Zur Übersicht“. Schlägt ein Schritt fehl, greift der bisherige Weg mit separater Anmeldung.
- Regressionstests für den HTML-Parser auf anonymisierten Seitenaufnahmen (`swift test`, 41 Tests).

## Frühere Versionen

iOS 1.6 und macOS 1.2 und älter: siehe Git-Historie und App-Store-Versionshinweise.
