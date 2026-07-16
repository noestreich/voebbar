# Datenschutzerklärung — VÖPP

*Stand: Juli 2026*

VÖPP ist ein privates, nicht-kommerzielles Projekt und steht in keiner Verbindung zum
Verbund der Öffentlichen Bibliotheken Berlins (VÖBB) oder zur ZLB.

## Kurzfassung

**VÖPP erhebt, speichert und überträgt keinerlei Daten an den Entwickler oder an Dritte.**
Es gibt keine Analyse-, Tracking- oder Werbe-Komponenten und keine eigenen Server.

## Welche Daten verarbeitet die App?

- **Ausweisnummer und Name deiner Bibliothekskonten** — gespeichert ausschließlich lokal auf
  deinem Gerät (UserDefaults).
- **Passwörter deiner Bibliothekskonten** — gespeichert ausschließlich im Schlüsselbund
  (Keychain) deines Geräts. Sie verlassen das Gerät nur zur Anmeldung bei der offiziellen
  VÖBB-Webseite (siehe unten).
- **Ausleihdaten (Titel, Fälligkeitsdaten, Gebühren)** — werden von der VÖBB-Webseite
  abgerufen und lokal auf dem Gerät zwischengespeichert, damit die App beim Start sofort den
  letzten Stand anzeigen kann.

## Wohin verbindet sich die App?

Die App kommuniziert ausschließlich mit der offiziellen Webseite des VÖBB
(**https://www.voebb.de**) — verschlüsselt per HTTPS und nur mit den Zugangsdaten, die du
selbst hinterlegt hast. Es gelten dabei die Datenschutzbestimmungen des VÖBB. Es findet keine
Kommunikation mit anderen Servern statt.

## Kamera

Die Kamera wird ausschließlich verwendet, um auf Wunsch den Barcode auf der Rückseite des
Bibliotheksausweises zu scannen und die Ausweisnummer in das Formular zu übernehmen. Es werden
keine Fotos oder Videos gespeichert oder übertragen.

## Benachrichtigungen

Erinnerungen an anstehende Rückgabedaten werden als lokale Benachrichtigungen direkt auf dem
Gerät geplant. Es kommen keine Push-Server zum Einsatz.

## Löschen der Daten

Alle Daten werden mit dem Löschen der App bzw. der Konten in der App vollständig entfernt.

## Kontakt

Fragen zu dieser Datenschutzerklärung: über die Issues des GitHub-Repositories
https://github.com/noestreich/voebbar
