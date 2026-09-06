#!/usr/bin/env python3
"""
Erzeugt anonymisierte HTML-Fixtures für die VOEBBKit-Tests aus einer HAR-Aufzeichnung
einer voebb.de-Sitzung (Login → Kontoübersicht → Ausleihen).

    python3 Tests/VOEBBKitTests/anonymize_fixtures.py /pfad/zur/aufzeichnung.har

Die rohe HAR darf NIE committet werden. Ersetzt werden: Name, Ausweisnummer, Session-IDs,
Identity-Tokens, Mediennummern, Abholcode sowie Titel/Autoren (wortweise, strukturerhaltend —
Satzzeichen, "¬", "[Comic]" und Platzhalter wie "/ X" bleiben stehen). Bibliotheksnamen und
Datumsangaben sind keine personenbezogenen Daten und bleiben unverändert.
"""
import base64
import json
import re
import sys
from pathlib import Path

OUT_DIR = Path(__file__).parent / "Fixtures"


def load_entries(har_path):
    with open(har_path) as f:
        har = json.load(f)
    return har["log"]["entries"]


def body(entry):
    c = entry["response"]["content"]
    text = c.get("text", "")
    if c.get("encoding") == "base64":
        text = base64.b64decode(text).decode("utf-8", errors="replace")
    return text


def find_pages(entries):
    """Kontoübersicht + Ausleihseite anhand des <title> finden; Zugangsdaten aus dem Login-POST."""
    overview = loans = None
    card = None
    for e in entries:
        req = e["request"]
        if "logincheck" in req["url"] and req["method"] == "POST":
            params = dict(x.split("=", 1) for x in req.get("postData", {}).get("text", "").split("&") if "=" in x)
            card = params.get("L%23AUSW", params.get("L#AUSW"))
        html = body(e)
        if "<title>" not in html:
            continue
        title = re.search(r"<title>(.*?)</title>", html, re.DOTALL).group(1)
        if "Mein Konto" in title and overview is None:
            overview = html
        elif "Meine Ausleihen" in title and loans is None:
            loans = html
    if not (overview and loans):
        sys.exit("HAR enthält keine vollständige Übersicht/Ausleihseite (Netzwerk-Filter 'Alle' nutzen!)")
    return overview, loans, card


class WordMapper:
    """Bildet jedes Wort deterministisch auf ein Pseudowort ab (W1, W2, …) — gleiche Wörter → gleiches Pseudowort."""

    def __init__(self):
        self.map = {}

    def __call__(self, html_fragment):
        def repl(m):
            w = m.group(0)
            if len(w) <= 1:  # Platzhalter wie "X" bleiben — Parser-Sonderfall
                return w
            if w not in self.map:
                self.map[w] = f"W{len(self.map) + 1}"
            return self.map[w]
        # Nur Text zwischen Tags ersetzen — <br> & Co. müssen unangetastet bleiben
        parts = re.split(r"(<[^>]+>)", html_fragment)
        return "".join(
            p if p.startswith("<") else re.sub(r"[^\W\d_]+", repl, p)  # alle Unicode-Buchstaben
            for p in parts
        )


def anonymize(html, name_variants, card, mapper):
    # Titel-/Autorenzellen: 4. <td> jeder Ausleihzeile wortweise ersetzen
    def anon_row(m):
        row = m.group(0)
        tds = list(re.finditer(r"(<td[^>]*>)(.*?)(</td>)", row, re.DOTALL))
        if len(tds) < 5:
            return row
        title_td = tds[3]
        inner = title_td.group(2)
        # Mediennummer (letzte Zeile, 11 Ziffern) durch Zähler ersetzen, Rest wortweise
        inner = re.sub(r"\b\d{11}\b", lambda _: f"{anon_row.counter:011d}", inner)
        anon_row.counter += 1
        inner = mapper(inner)
        return row[: title_td.start(2)] + inner + row[title_td.end(2):]
    anon_row.counter = 1

    html = re.sub(r"<tr[^>]*class=\"[^\"]*rTable_tr[^\"]*\"[^>]*>.*?</tr>", anon_row, html, flags=re.DOTALL)

    for variant in name_variants:
        html = html.replace(variant, "Muster, Erika" if "," in variant else "Erika Muster")
    if card:
        html = html.replace(card, "00000000000")
    html = re.sub(r"/aDISWeb/_[a-z0-9]+/", "/aDISWeb/_sessionidredacted/", html)
    html = re.sub(r"(name=\"identity\"[^>]*value=\")[^\"]*(\")", r"\1IDENTITY_REDACTED\2", html)
    html = re.sub(r"(value=\")[^\"]*(\"[^>]*name=\"identity\")", r"\1IDENTITY_REDACTED\2", html)
    html = re.sub(r"(<dd class=\"adis-value\">\s*)\d{2} [A-Za-z]{2}(\s*</dd>)", r"\g<1>00 Xx\2", html)
    html = re.sub(r"Abholcode: \d{2} [A-Za-z]{2}", "Abholcode: 00 Xx", html)
    return html


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    entries = load_entries(sys.argv[1])
    overview, loans, card = find_pages(entries)

    # Name aus "Hallo Vorname Nachname" der Übersicht ableiten
    m = re.search(r"Hallo\s+([A-ZÄÖÜ][^\s<]+)\s+([A-ZÄÖÜ][^\s<]+)", overview)
    if not m:
        sys.exit("Name nicht gefunden")
    first, last = m.group(1), m.group(2)
    name_variants = [f"{last}, {first}", f"{first} {last}"]

    mapper = WordMapper()
    OUT_DIR.mkdir(exist_ok=True)
    for filename, html in [("overview.html", overview), ("loans.html", loans)]:
        out = anonymize(html, name_variants, card, mapper)
        # Leak-Check
        for needle in [first, last, card or "§§"]:
            if needle and needle in out:
                sys.exit(f"LEAK: '{needle}' noch in {filename}")
        (OUT_DIR / filename).write_text(out, encoding="utf-8")
        print(f"{filename}: {len(out)} Zeichen")


if __name__ == "__main__":
    main()
