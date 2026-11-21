# Jingles

Kleiner macOS-Prototyp für Planlosgelöst. Jingles merkt sich eine WAV-Datei und spielt sie über die aktuelle macOS-Tonausgabe ab. Dieselbe Taste pausiert die Wiedergabe und setzt sie an der gleichen Stelle fort.

## App bauen und öffnen

```sh
./build.sh --install
open "$HOME/Applications/Jingles.app"
```

Der Build verwendet die macOS-Command-Line-Tools von Apple. Die lokal signierte App hat die Bundle-ID `de.maikpurrmann.jingles`. Für den OBS-Test immer die installierte App am selben Ort starten und vor einem Neubau beenden.

## Stream Deck

1. Einer freien Taste **System → Webseite** zuweisen.
2. Als URL `http://127.0.0.1:17639/toggle` eintragen und **GET-Anfrage im Hintergrund** auswählen.
3. Jingles öffnen, eine WAV auswählen und das Fenster minimieren. Die Taste abwechselnd für Wiedergabe und Pause drücken.

Die App muss dabei laufen. Für einen lokalen Test ohne Stream Deck gibt der gleiche Aufruf den neuen Zustand zurück.

```sh
curl -fsS http://127.0.0.1:17639/toggle
```

## OBS

1. Jingles öffnen und die WAV kurz abspielen.
2. In OBS **macOS-Audioaufnahme → Anwendungsaudioaufnahme → Jingles** als eigene Quelle wählen.
3. Für die separate Jingle-Aufnahme die Quelle **Spur 3** zuordnen, bei Bedarf zusätzlich **Spur 1** für den Abhörmix. **Spur 2** ist für das Mikrofon vorgesehen.
4. Jingles beenden und am selben Installationsort neu öffnen. Abspielen und prüfen, ob die vorhandene OBS-Quelle wieder ausschlägt. Eine kurze MKV-Probe zeigt, ob die Spurzuordnung stimmt.

Der Kopfhörer folgt der macOS-Tonausgabe. Für die bestehende VDO.Ninja-Verbindung geht die gespeicherte OBS-Monitoringroute über BlackHole. Bei Bedarf Audiomonitoring für diese Quelle aktivieren.
