# Jingles

Kleiner macOS-Prototyp für Planlosgelöst. In **Jingles** einmal einen Ordner auswählen. Die App zeigt dessen WAV- und MP3-Dateien an und spielt immer eine Datei über die aktuelle macOS-Tonausgabe ab. Über **Aktualisieren** liest sie den Ordner erneut ein. Unterordner bleiben außen vor.

In der App hält **Pause** die Wiedergabeposition. **Abspielen** setzt dort fort. **Stopp** setzt die Position zurück, damit das nächste **Abspielen** den Einspieler von Anfang an startet. Die Abspieltaste direkt neben einem Dateinamen startet die jeweilige Datei von Anfang an.

## App bauen und öffnen

```sh
./build.sh --install
open "$HOME/Applications/Jingles.app"
```

Der Build verwendet die macOS-Command-Line-Tools von Apple. Die lokal signierte App hat die Bundle-ID `de.maikpurrmann.jingles`. Für den OBS-Test immer die installierte App am selben Ort starten und vor einem Neubau beenden.

## Stream Deck

1. Einer freien Taste **System → Webseite** zuweisen.
2. In Jingles neben dem gewünschten Einspieler **Link kopieren** wählen und den Link als URL einfügen.
3. **GET-Anfrage im Hintergrund** auswählen. Ein Druck startet den Einspieler. Ein weiterer Druck auf dieselbe Taste stoppt den laufenden Einspieler. Beim nächsten Druck beginnt er wieder von Anfang an. Die Taste eines anderen Einspielers wechselt direkt zu dieser Datei. Das funktioniert auch, wenn Jingles minimiert ist.

Der Link verweist auf den Dateinamen im ausgewählten Ordner. Weitere Dateien und eine geänderte Sortierung beeinflussen ihn nicht. Bei einer gleichnamigen Ersatzdatei liest die App beim Neustart des Einspielers die neue Fassung. Nach einem Umbenennen, Löschen oder Ändern der Endung meldet die App die fehlende Datei. Nach einem Umbenennen den neuen Link kopieren.

Die App muss dabei laufen. Maiks vorhandene Taste **Jingles** auf **Seite 4, zweite Reihe, vorletzte Spalte** verwendet weiterhin den folgenden Link für Play/Pause und setzt an derselben Stelle fort. Nach dem Öffnen verwendet sie den letzten Einspieler oder, bei einem neu ausgewählten Ordner, den ersten Eintrag.

```sh
curl -fsS http://127.0.0.1:17639/toggle
```

## OBS

1. Jingles öffnen und einen Einspieler kurz abspielen.
2. In OBS **macOS-Audioaufnahme → Anwendungsaudioaufnahme → Jingles** als eigene Quelle wählen.
3. Für die separate Jingle-Aufnahme die Quelle **Spur 3** zuordnen, bei Bedarf zusätzlich **Spur 1** für den Abhörmix. **Spur 2** ist für das Mikrofon vorgesehen.
4. Jingles beenden und am selben Installationsort neu öffnen. Abspielen und prüfen, ob die vorhandene OBS-Quelle wieder ausschlägt. Eine kurze MKV-Probe zeigt, ob die Spurzuordnung stimmt.

## Kopfhörer und VDO.Ninja

Für den Kopfhörer am Audient iD14 das Audient als macOS-Tonausgabe verwenden. In OBS ist **BlackHole 2ch** das Monitoringgerät. Das Audiomonitoring für **Audient iD14** und **Jingles** aktivieren und in VDO.Ninja **BlackHole 2ch** als Audioeingang wählen.

## Teststand vom 21.11.2026

- OBS hat die App nach einem Jingles-Neustart wiedererkannt. Maiks MKV-Probe bestätigt **Spur 1 Abhörmix**, **Spur 2 Mikrofon** und **Spur 3 Jingles**.
- Mit der Ordnerliste wurden `01_PLG_Intro.wav` und `02_PLG_Outro.mp3` über ihre Einzel-Links gestartet. Beide Einspieler sind in der OBS-Probe auf **Spur 3** nachweisbar. Maik bestätigte das Kopieren und Belegen der Links am Stream Deck. Die aktualisierte Start-/Stopp-Logik verwendet dieselben Links.
- Maik hat die WAV über VDO.Ninja auf seinem MacBook als Gegenstelle gehört. Der gemeinsame Hörtest mit Christian ist offen.
- Das Absenken auf **10 %** und der langsame Fade zurück auf **100 %** sind noch offen.
