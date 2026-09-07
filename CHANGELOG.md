# Changelog

Versionen von VÖPP (iOS) und VOEBBMenu (macOS). Beide Apps teilen sich `VOEBBKit`, Änderungen daran gelten für beide.

## iOS 1.7 / macOS 1.3 — 2026-09-07

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
