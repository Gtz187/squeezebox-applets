# Squeezebox-Radio-Applets: Wetter-Uhr & Eieruhr

Zwei Applets für das **Logitech Squeezebox Radio**, verteilt über ein kleines
Plugin für den **Lyrion Music Server (LMS)**:

| Applet | Was es macht |
|---|---|
| **Wetter-Uhr** | Menüpunkt „Wetter“ im Hauptmenü und Bildschirmschoner „Wetter-Uhr“: große Uhr, aktuelles Wetter, 3-Tage-Vorhersage mit eigenen Symbolen. Beim Abspielen stehen unten Sender und Titel. Läuft die Eieruhr, zeigt die Uhr die Restzeit. Auf Wunsch wechseln sich die nächsten Termine aus einem CalDAV-Kalender mit der Vorhersage ab. Daten von [Open-Meteo](https://open-meteo.com) (kostenlos, ohne API-Key). **Ort frei wählbar.** |
| **Eieruhr** | Küchentimer: Zeit mit dem Drehrad einstellen (30-s-Schritte unter 10 min, 1 min unter 60 min, darüber 5 min), Rad drücken = Start. Während des Countdowns: Rad = Zeit ändern, drücken = Stopp. Am Ende Piepton und „Fertig!“ bis zum Tastendruck (max. 3 min). Die letzte Zeit wird gemerkt. |

Die Oberfläche ist deutsch.

## Installation

Voraussetzung: LMS ab 8.0 und ein Squeezebox Radio, das mit diesem LMS verbunden
ist. Getestet mit LMS 9.1 und der Community-Firmware 9.0.1 auf dem Radio.

1. **Repository im LMS eintragen**
   LMS-Weboberfläche → *Einstellungen* → *Plugins* → ganz unten bei
   *Zusätzliche Repositories* diese URL eintragen und *Übernehmen*:

   ```
   https://raw.githubusercontent.com/Gtz187/squeezebox-applets/main/repo.xml
   ```

2. **Plugin installieren**
   In der Plugin-Liste erscheint jetzt **Radio-Applets (Wetter-Uhr, Eieruhr)**.
   Haken setzen, *Übernehmen*, LMS neu starten, wenn er danach fragt.

3. **Applets auf dem Radio installieren**
   Am Radio: *Einstellungen* → *Erweitert* → *Applet-Installer*. Dort stehen
   *Wetter-Uhr* und *Eieruhr*. Auswählen und installieren, das Radio startet neu.

4. **Ort einstellen**
   Hauptmenü → *Wetter* → ganz unten *Ort ändern* → Ortsnamen eintippen →
   aus der Trefferliste wählen. Ohne Einstellung zeigt die Wetter-Uhr Glauchau.

5. **Termine (optional)**
   LMS-Weboberfläche → *Einstellungen* → *Plugins* → *Radio-Applets* → *Einstellungen*:
   CalDAV-Adresse des Kalenders, Benutzer und Passwort eintragen. Beispiel Baïkal:

   ```
   http://mein-server:8099/dav.php/calendars/<benutzer>/<kalender>/
   ```

   Am besten einen eigenen Benutzer anlegen, der den Kalender nur lesen darf.
   Der LMS fragt den Kalender alle 15 min ab (Basic- oder Digest-Anmeldung) und
   lässt Serientermine vom Server auflösen. Ein reiner ICS-Link (z. B. die
   iCal-Adresse von Google) geht nicht, weil dort Serientermine nicht aufgelöst sind.
   Die Wetter-Uhr zeigt dann im Wechsel (alle 8 s) die Vorhersage und die
   nächsten 6 Termine einzeilig (beim Abspielen 4), mit dem Drehrad blättert man von Hand.
   Im Menü *Wetter* stehen die nächsten 5 Termine unten.

   Die Zugangsdaten liegen nur in den LMS-Einstellungen. Die Termine selbst liefert
   der LMS ohne Anmeldung unter `/radioapplets/termine.json` an das Radio aus,
   also für jeden im Heimnetz lesbar.

Die Wetter-Uhr trägt sich beim ersten Start selbst als Bildschirmschoner ein
(bei Stopp und bei Wiedergabe). Ändern lässt sich das wie gewohnt unter
*Einstellungen* → *Bildschirm* → *Bildschirmschoner*.

### Updates

Neue Versionen kommen in zwei Stufen:

1. Der LMS bietet unter *Einstellungen* → *Plugins* ein Update für *Radio-Applets* an.
2. Danach bietet das Radio im *Applet-Installer* die neuen Applet-Versionen an.
   Ist dort *Automatisch aktualisieren* aktiv, installiert das Radio sie nach
   einem Firmware-Update auch von selbst wieder.

## Warum ein Plugin und nicht nur die Applets im Repository?

Die `repo.xml` des LMS kann Applets auch direkt anbieten. Dann lädt aber das
Radio die Zips selbst, und das schafft die alte Radio-Firmware bei HTTPS-Adressen
wie GitHub nicht. Das Plugin bringt die Applets deshalb mit und reicht sie
über den LMS per HTTP ans Radio weiter. Nebenbei taucht es so in der
Plugin-Liste des LMS auf.

## Aufbau

```
applets/Wetter/        Wetter-Uhr (Lua, SqueezePlay)
applets/Eieruhr/       Eieruhr (Lua, SqueezePlay)
plugin/RadioApplets/   LMS-Plugin (Perl): bietet die Applets dem Applet-Installer an,
                       holt die Termine (Calendar.pm, Einstellungen: Settings.pm)
tools/build.py         baut Applet-Zips, Plugin-Zip (dist/) und repo.xml
tools/mkicons.py       zeichnet die Wettersymbole (Pillow)
dist/                  fertige Plugin-Zips, auf die repo.xml verweist
repo.xml               Repository-Datei für den LMS (erzeugt)
```

## Selbst bauen und ändern

```sh
python3 tools/build.py
```

Das Skript packt jedes Applet nach `plugin/RadioApplets/applets/`, baut daraus
`dist/RadioApplets-<Version>.zip` und schreibt die `repo.xml` mit der
SHA1-Prüfsumme.

Bei Änderungen in `tools/build.py`:

- die Version des geänderten Applets in `APPLETS` hochzählen, sonst bietet das Radio kein Update an
- `PLUGIN_VERSION` hochzählen, sonst bietet der LMS kein Update an
- für einen eigenen Fork `REPO_URL` und `RAW_URL` anpassen

Zum Testen ohne GitHub lässt sich das Plugin direkt in einen LMS kopieren:

```sh
python3 tools/build.py --deploy root@mein-server:/pfad/zu/cache/InstalledPlugins/Plugins
```

Neue Applet-Versionen braucht der LMS nicht neu einzulesen. Nur nach
Änderungen an `Plugin.pm` muss er neu starten.

### Hinweise für eigene Applets

- Jede neu erzeugte Surface (`Surface:drawText`, `Surface:newRGBA`) nach Gebrauch
  mit `:release()` freigeben. Der Lua-Garbage-Collector sieht den C-Speicher
  nicht. Sonst läuft der Speicher voll, `jive` stürzt ab und der Watchdog startet
  das Radio neu.
- Schließt sich das letzte per `tieWindow` gebundene Fenster, entlädt SqueezePlay
  das Applet. Deshalb erst das neue Fenster öffnen, dann das alte schließen.
- Das Radio kann kein modernes HTTPS. Open-Meteo geht zum Glück auch per HTTP.
- Bildschirmfoto per SSH: `cat /dev/fb0` liefert 240×320 RGB565 (hochkant),
  um 90° drehen.

### Eieruhr fernsteuern

Die Eieruhr schaut jede Sekunde nach der Datei `/tmp/eieruhr` auf dem Radio:

```sh
echo 300 | ssh root@radio 'cat > /tmp/eieruhr'   # 5 Minuten starten
echo 0   | ssh root@radio 'cat > /tmp/eieruhr'   # stoppen
```

## Lizenz

MIT, siehe [LICENSE](LICENSE). Wetterdaten: [Open-Meteo](https://open-meteo.com), CC BY 4.0.
