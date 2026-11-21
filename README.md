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

Die App muss dabei laufen. Maiks Taste **Jingles** liegt auf dem Stream Deck XL auf **Seite 4, zweite Reihe, vorletzte Spalte**. Play, Pause und Fortsetzen mit Jingles im Hintergrund sind geprüft. Für einen lokalen Test ohne Stream Deck gibt der gleiche Aufruf den neuen Zustand zurück.

```sh
curl -fsS http://127.0.0.1:17639/toggle
```

## OBS

1. Jingles öffnen und die WAV kurz abspielen.
2. In OBS **macOS-Audioaufnahme → Anwendungsaudioaufnahme → Jingles** als eigene Quelle wählen.
3. Für die separate Jingle-Aufnahme die Quelle **Spur 3** zuordnen, bei Bedarf zusätzlich **Spur 1** für den Abhörmix. **Spur 2** ist für das Mikrofon vorgesehen.
4. Jingles beenden und am selben Installationsort neu öffnen. Abspielen und prüfen, ob die vorhandene OBS-Quelle wieder ausschlägt. Eine kurze MKV-Probe zeigt, ob die Spurzuordnung stimmt.

## Kopfhörer und VDO.Ninja

Für den Kopfhörer am Audient iD14 das Audient als macOS-Tonausgabe verwenden. In OBS ist **BlackHole 2ch** das Monitoringgerät. Das Audiomonitoring für **Audient iD14** und **Jingles** aktivieren und in VDO.Ninja **BlackHole 2ch** als Audioeingang wählen.

## Teststand vom 21.11.2026

- OBS hat die App nach einem Jingles-Neustart wiedererkannt. Maiks MKV-Probe bestätigt **Spur 1 Abhörmix**, **Spur 2 Mikrofon** und **Spur 3 Jingles**.
- Maik hat die WAV über VDO.Ninja auf seinem MacBook als Gegenstelle gehört. Der gemeinsame Hörtest mit Christian ist offen.
- Das Absenken auf **10 %** und der langsame Fade zurück auf **100 %** sind noch offen.
