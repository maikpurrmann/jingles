import AppKit
import SwiftUI

/// The Retro appearance: a compact late-90s desktop player look with a pixel display,
/// a level analyzer, fade sliders and a green-on-black playlist. Original artwork, no skin assets.
enum RetroPalette {
    static let window = Color(red: 0.075, green: 0.075, blue: 0.095)
    static let panelTop = Color(red: 0.25, green: 0.26, blue: 0.33)
    static let panelBottom = Color(red: 0.15, green: 0.155, blue: 0.20)
    static let lcd = Color(red: 0.015, green: 0.03, blue: 0.02)
    static let green = Color(red: 0.12, green: 0.95, blue: 0.28)
    static let greenInk = NSColor(srgbRed: 0.12, green: 0.95, blue: 0.28, alpha: 1)
    static let yellow = Color(red: 0.98, green: 0.86, blue: 0.18)
    static let red = Color(red: 0.98, green: 0.26, blue: 0.16)
    static let gold = Color(red: 0.83, green: 0.73, blue: 0.47)
    static let listText = Color(red: 0.10, green: 0.88, blue: 0.20)
    static let listSelection = Color(red: 0.06, green: 0.13, blue: 0.62)
}

struct RetroPlayerView: View {
    @ObservedObject var player: JinglePlayer
    private var showsInfo = State(initialValue: false)
    private var sliderNote = State<String?>(initialValue: nil)

    var body: some View {
        VStack(spacing: 8) {
            mainPanel
            playlistPanel
            statusLines
        }
        .padding(10)
        .frame(minWidth: 560, minHeight: 440)
        .background(RetroPalette.window)
    }

    // MARK: Main panel

    private var mainPanel: some View {
        VStack(spacing: 7) {
            RetroTitleStrip(title: "Jingles", detail: player.folder?.lastPathComponent)
            HStack(alignment: .top, spacing: 8) {
                RetroDisplay(player: player)
                VStack(alignment: .leading, spacing: 7) {
                    RetroMarquee(text: sliderNote.wrappedValue ?? marqueeText,
                                 running: sliderNote.wrappedValue == nil)
                    infoRow
                    fadeRow
                }
            }
            PlaybackProgressBar(progress: player.playbackProgress, duration: player.playbackDuration,
                                run: player.canPause ? player.playbackRun : nil,
                                tint: RetroPalette.greenInk)
                .frame(height: 5)
                .padding(2)
                .retroInset()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Wiedergabefortschritt")
                .accessibilityValue("\(Int(player.playbackProgress * 100)) Prozent")
            controlsRow
        }
        .padding(8)
        .retroPanel()
    }

    private var marqueeText: String {
        guard let name = player.currentFilename, player.canStop else {
            var parts = ["Jingles"]
            if let selected = player.selectedFilename {
                let seconds = player.files.first { $0.lastPathComponent == selected }.flatMap { player.durations[$0] }
                parts.append("Bereit: \(selected) (\(timeLabel(seconds)))")
            }
            if let folder = player.folder {
                parts.append("\(player.files.count) Jingles in \(folder.lastPathComponent)")
            } else {
                parts.append("Ordner mit ⏏ wählen")
            }
            return parts.joined(separator: "   ***   ")
        }
        let index = player.files.firstIndex { $0.lastPathComponent == name }.map { "\($0 + 1). " } ?? ""
        let seconds = player.files.first { $0.lastPathComponent == name }.flatMap { player.durations[$0] }
        let state = player.canPause ? "" : "  [Pause]"
        return "\(index)\(name) (\(timeLabel(seconds)))\(state)"
    }

    private var infoRow: some View {
        let rate = player.canStop ? player.playbackSampleRate.map { "\(Int(($0 / 1000).rounded()))" } : nil
        let channels = player.canStop ? player.playbackChannelCount : nil
        return HStack(spacing: 4) {
            RetroLevelField(player: player)
            RetroCaption(text: "% Pegel")
                .padding(.trailing, 6)
            RetroField(text: rate ?? "", width: 26)
            RetroCaption(text: "kHz")
            Spacer(minLength: 6)
            RetroLamp(title: "Mono", lit: channels == 1)
            RetroLamp(title: "Stereo", lit: (channels ?? 0) > 1)
            RetroLamp(title: "Fade", lit: player.isLowered, color: RetroPalette.yellow)
        }
    }

    private var targetLevel: Binding<Double> {
        Binding(get: { Double(player.loweredPercent) },
                set: { player.loweredPercent = Int($0.rounded()) })
    }

    private var fadeRow: some View {
        let level = player.isLowered ? player.loweredPercent : 100
        let action = player.isLowered ? "Auf 100 % anheben" : "Auf \(player.loweredPercent) % absenken"
        let note: (String?) -> Void = { sliderNote.wrappedValue = $0 }
        return HStack(alignment: .top, spacing: 7) {
            RetroHSlider("Ziel", value: targetLevel, range: 0...100, step: 1, unit: "%", onEditing: note)
                .frame(maxWidth: .infinity)
            RetroHSlider("Runter", value: $player.fadeDownSeconds, range: 0...30, step: 0.1, unit: "s",
                         curve: 2, onEditing: note)
                .frame(width: 58)
            RetroHSlider("Hoch", value: $player.fadeUpSeconds, range: 0...30, step: 0.1, unit: "s",
                         curve: 2, onEditing: note)
                .frame(width: 58)
            Button {
                player.toggleFade()
            } label: {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(player.isLowered ? RetroPalette.yellow : Color(white: 0.22))
                        .frame(width: 5, height: 5)
                        .shadow(color: player.isLowered ? RetroPalette.yellow : .clear, radius: 2)
                    Text("FADE")
                }
            }
            .buttonStyle(RetroButtonStyle(compact: true))
            .help(action)
            .accessibilityLabel("Fade")
            .accessibilityValue("\(player.isLowered ? "Abgesenkt" : "Normal"), \(level) Prozent")
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 3) {
            Button {
                player.play()
            } label: {
                Label("Abspielen", systemImage: "play.fill")
            }
            .help("Abspielen")
            .disabled(!player.canPlay)
            Button(action: player.pause) {
                Label("Pause", systemImage: "pause.fill")
            }
            .help("Pause")
            .disabled(!player.canPause)
            Button(action: player.stop) {
                Label("Stopp", systemImage: "stop.fill")
            }
            .help("Stopp")
            .disabled(!player.canStop)
            Button(action: player.chooseFolder) {
                Label("Ordner auswählen", systemImage: "eject.fill")
            }
            .help("Ordner auswählen")
            .padding(.leading, 6)
            Spacer(minLength: 6)
            Button(action: player.refresh) {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .help("Ordner aktualisieren")
            .disabled(player.folder == nil)
            Button {
                showsInfo.wrappedValue.toggle()
            } label: {
                Label("Info und Bedienhilfe", systemImage: "info")
            }
            .help("Info und Bedienhilfe")
            .popover(isPresented: showsInfo.projectedValue, arrowEdge: .bottom) {
                JinglesInfoView()
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(RetroButtonStyle())
    }

    // MARK: Playlist

    private var playlistPanel: some View {
        let total = player.files.compactMap { player.durations[$0] }.reduce(0, +)
        return VStack(spacing: 7) {
            RetroTitleStrip(title: "Playlist")
            Group {
                if player.files.isEmpty {
                    Text(player.folder == nil
                         ? "Ordner mit WAV- oder MP3-Dateien wählen (⏏)."
                         : "In diesem Ordner sind keine WAV- oder MP3-Dateien.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(RetroPalette.listText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(player.files.enumerated()), id: \.element) { index, file in
                                playlistRow(index: index, file: file)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
            .retroInset()
            HStack {
                Text("\(player.files.count) Jingles")
                Spacer()
                Text("Gesamt \(timeLabel(total))")
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .textCase(.uppercase)
            .foregroundStyle(RetroPalette.gold)
            .padding(.horizontal, 2)
        }
        .padding(8)
        .retroPanel()
    }

    private func playlistRow(index: Int, file: URL) -> some View {
        let name = file.lastPathComponent
        let isCurrent = name == player.currentFilename && player.canStop
        let selected = name == player.selectedFilename
        let seconds = isCurrent ? player.remainingSeconds : player.durations[file]
        let ink = isCurrent ? Color.white : RetroPalette.listText
        return HStack(spacing: 6) {
            Text("\(index + 1).")
                .frame(width: 30, alignment: .trailing)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(timeLabel(seconds))
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: isCurrent ? .bold : .regular, design: .monospaced))
        .foregroundStyle(ink)
        .padding(.horizontal, 6)
        .frame(height: 19)
        .background(selected ? RetroPalette.listSelection : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            player.select(name)
            player.play(named: name)
        }
        .simultaneousGesture(TapGesture().onEnded { player.select(name) })
        .contextMenu {
            Button("Von vorn abspielen") {
                player.select(name)
                player.play(named: name)
            }
        }
        .help("Klick wählt „\(name)“ vor, Doppelklick spielt ihn von vorn")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Von vorn abspielen") {
            player.select(name)
            player.play(named: name)
        }
    }

    @ViewBuilder
    private var statusLines: some View {
        let lines: [(String, Color)] = [
            player.message.map { ($0, RetroPalette.green) },
            player.playbackError.map { ($0, RetroPalette.red) },
            player.remoteError.map { ($0, RetroPalette.red) }
        ].compactMap { $0 }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(lines[index].0).foregroundStyle(lines[index].1)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timeLabel(_ seconds: Int?) -> String {
        guard let seconds else { return "-:--" }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

// MARK: - Display

private struct RetroDisplay: View {
    @ObservedObject var player: JinglePlayer

    var body: some View {
        let paused = player.canStop && !player.canPause
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 4) {
                    Image(systemName: player.canPause ? "play.fill" : paused ? "pause.fill" : "stop.fill")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(player.canStop ? RetroPalette.green : RetroPalette.green.opacity(0.35))
                    Text(paused ? "PAUSE" : player.canPause ? "PLAY" : "BEREIT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(RetroPalette.green.opacity(0.7))
                }
                .frame(width: 30)
                clock(paused: paused)
            }
            RetroAnalyzer(player: player)
                .frame(height: 30)
        }
        .padding(7)
        .frame(width: 168)
        .retroInset()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paused ? "Restzeit, pausiert" : "Restzeit")
        .accessibilityValue((player.remainingSeconds ?? selectedSeconds)
            .map { "\($0 / 60) Minuten \($0 % 60) Sekunden" } ?? "Keine")
    }

    @ViewBuilder
    private func clock(paused: Bool) -> some View {
        if let seconds = player.remainingSeconds {
            let text = "-\(seconds / 60):\(String(format: "%02d", seconds % 60))"
            if paused {
                TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                    let on = Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                    RetroDigits(text: text, pixel: 3.4, lit: on)
                }
            } else {
                RetroDigits(text: text, pixel: 3.4)
            }
        } else if let seconds = selectedSeconds {
            RetroDigits(text: " \(seconds / 60):\(String(format: "%02d", seconds % 60))", pixel: 3.4)
        } else {
            RetroDigits(text: " 0:00", pixel: 3.4, lit: false)
        }
    }

    private var selectedSeconds: Int? {
        player.files.first { $0.lastPathComponent == player.selectedFilename }.flatMap { player.durations[$0] }
    }
}

/// 5×7 pixel digits with faint unlit pixels, drawn in a Canvas.
struct RetroDigits: View {
    let text: String
    let pixel: CGFloat
    var lit = true
    var color = RetroPalette.green

    private static let glyphs: [Character: [String]] = [
        "0": [".XXX.", "X...X", "X..XX", "X.X.X", "XX..X", "X...X", ".XXX."],
        "1": ["..X..", ".XX..", "..X..", "..X..", "..X..", "..X..", ".XXX."],
        "2": [".XXX.", "X...X", "....X", "...X.", "..X..", ".X...", "XXXXX"],
        "3": ["XXXXX", "...X.", "..X..", "...X.", "....X", "X...X", ".XXX."],
        "4": ["...X.", "..XX.", ".X.X.", "X..X.", "XXXXX", "...X.", "...X."],
        "5": ["XXXXX", "X....", "XXXX.", "....X", "....X", "X...X", ".XXX."],
        "6": ["..XX.", ".X...", "X....", "XXXX.", "X...X", "X...X", ".XXX."],
        "7": ["XXXXX", "....X", "...X.", "..X..", ".X...", ".X...", ".X..."],
        "8": [".XXX.", "X...X", "X...X", ".XXX.", "X...X", "X...X", ".XXX."],
        "9": [".XXX.", "X...X", "X...X", ".XXXX", "....X", "...X.", ".XX.."],
        "-": [".....", ".....", ".....", ".XXX.", ".....", ".....", "....."],
        ":": [".", ".", "X", ".", "X", ".", "."],
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."]
    ]

    var body: some View {
        let rows = text.map { Self.glyphs[$0] ?? Self.glyphs[" "]! }.map { $0.map(Array.init) }
        let columns = rows.reduce(0) { $0 + $1[0].count } + max(rows.count - 1, 0)
        Canvas { context, _ in
            var x: CGFloat = 0
            for glyph in rows {
                for (row, line) in glyph.enumerated() {
                    for (column, mark) in line.enumerated() {
                        let rect = CGRect(x: x + CGFloat(column) * pixel, y: CGFloat(row) * pixel,
                                          width: pixel - 0.6, height: pixel - 0.6)
                        let on = lit && mark == "X"
                        context.fill(Path(rect), with: .color(on ? color : color.opacity(0.09)))
                    }
                }
                x += CGFloat(glyph[0].count + 1) * pixel
            }
        }
        .frame(width: CGFloat(columns) * pixel, height: 7 * pixel)
        .shadow(color: lit ? color.opacity(0.45) : .clear, radius: 3)
        .accessibilityHidden(true)
    }
}

/// Level analyzer. AVAudioPlayer only meters the overall level per channel, so the bars are
/// driven by that level with a per-band motion, not by a frequency analysis.
private struct RetroAnalyzer: View {
    @ObservedObject var player: JinglePlayer
    private var bands = State(initialValue: AnalyzerBands(count: 19))

    var body: some View {
        let playing = player.canPause
        let paused = player.canStop && !playing
        // Playing: follows the level. Paused: frozen. Stopped: a slow scanner sweep, so the display is never dead.
        TimelineView(.animation(minimumInterval: playing ? 1.0 / 30 : 1.0 / 15, paused: paused)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let bands = self.bands.wrappedValue
                if playing {
                    bands.advance(levels: player.meterLevels(), time: time)
                } else if !paused {
                    bands.idle(time: time)
                }
                let count = bands.bars.count
                let gap: CGFloat = 1.5
                let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                let segment: CGFloat = 2
                let segments = Int(size.height / (segment + 1))
                for band in 0..<count {
                    let x = CGFloat(band) * (width + gap)
                    let lit = Int((bands.bars[band] * Double(segments)).rounded())
                    for step in 0..<segments {
                        let y = size.height - CGFloat(step + 1) * (segment + 1)
                        let fraction = Double(step) / Double(segments)
                        let color = fraction > 0.82 ? RetroPalette.red
                            : fraction > 0.58 ? RetroPalette.yellow : RetroPalette.green
                        let rect = CGRect(x: x, y: y, width: width, height: segment)
                        context.fill(Path(rect), with: .color(step < lit ? color : color.opacity(0.06)))
                    }
                    if bands.peaks[band] > 0.02 {
                        let y = size.height - CGFloat(bands.peaks[band]) * size.height
                        context.fill(Path(CGRect(x: x, y: max(0, y - 1), width: width, height: 1.2)),
                                     with: .color(Color(white: 0.82)))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private final class AnalyzerBands {
    private(set) var bars: [Double]
    private(set) var peaks: [Double]
    private var holds: [Double]
    private var lastTime: TimeInterval?

    init(count: Int) {
        bars = Array(repeating: 0, count: count)
        peaks = bars
        holds = bars
    }

    func advance(levels: [Float], time: TimeInterval) {
        let level = Double(levels.max() ?? 0)
        let count = Double(bars.count)
        update(time: time) { band in
            let position = Double(band) / count
            let tilt = 1 - 0.32 * position
            let wobble = 0.62 + 0.38 * sin(time * (3.3 + Double(band) * 0.71) + Double(band) * 1.9)
                * sin(time * (1.1 + Double(band) * 0.29) + Double(band))
            return min(1, pow(level, 1.25) * tilt * wobble * 1.08)
        }
    }

    /// Idle pattern: a soft hump sweeping back and forth, with the usual peak caps trailing it.
    func idle(time: TimeInterval) {
        let last = Double(bars.count - 1)
        let center = (0.5 - 0.5 * cos(time * 1.15)) * last
        update(time: time) { band in
            let distance = Double(band) - center
            return 0.07 + 0.48 * exp(-distance * distance / 5)
        }
    }

    private func update(time: TimeInterval, target: (Int) -> Double) {
        let delta = min(max(time - (lastTime ?? time), 0), 0.1)
        lastTime = time
        for band in bars.indices {
            let target = target(band)
            bars[band] = max(target, bars[band] - 1.7 * delta)
            if bars[band] >= peaks[band] {
                peaks[band] = bars[band]
                holds[band] = 0.35
            } else if holds[band] > 0 {
                holds[band] -= delta
            } else {
                peaks[band] = max(0, peaks[band] - 0.8 * delta)
            }
        }
    }
}

/// A scrolling title line, as on old desktop players.
private struct RetroMarquee: View {
    let text: String
    let running: Bool

    var body: some View {
        let item = text + "   ***   "
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let itemWidth = max(1, (item as NSString).size(withAttributes: [.font: font]).width)
        GeometryReader { geometry in
            if running {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    let offset = (timeline.date.timeIntervalSinceReferenceDate * 30)
                        .truncatingRemainder(dividingBy: itemWidth)
                    HStack(spacing: 0) {
                        ForEach(0..<Int(geometry.size.width / itemWidth) + 2, id: \.self) { _ in
                            Text(item)
                        }
                    }
                    .fixedSize()
                    .offset(x: -offset)
                }
            } else {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: geometry.size.width, alignment: .leading)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(RetroPalette.green)
        .frame(height: 15)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .clipped()
        .retroInset()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct RetroField: View {
    let text: String
    let width: CGFloat
    var color = RetroPalette.green

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(width: width, height: 15)
            .retroInset()
    }
}

private struct RetroLamp: View {
    let title: String
    let lit: Bool
    var color = RetroPalette.green

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .textCase(.uppercase)
            .foregroundStyle(lit ? color : Color(white: 0.42))
            .shadow(color: lit ? color.opacity(0.7) : .clear, radius: 2)
            .accessibilityHidden(!lit)
    }
}

// MARK: - Fade controls

/// The jingle level right now, as a number field. Counts along while a fade runs.
private struct RetroLevelField: View {
    @ObservedObject var player: JinglePlayer

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !player.isFading)) { _ in
            let percent = Int((player.masterLevel * 100).rounded())
            RetroField(text: "\(percent)", width: 32,
                       color: player.isLowered ? RetroPalette.yellow : RetroPalette.green)
                .accessibilityLabel("Jingle-Pegel")
                .accessibilityValue("\(percent) Prozent")
        }
        .help("Aktueller Jingle-Pegel")
    }
}

private struct RetroCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(white: 0.78))
            .lineLimit(1)
            .fixedSize()
    }
}

/// Small horizontal slider like the volume control of old desktop players: the groove colour
/// follows the position. While dragging, `onEditing` reports a label for the title display.
private struct RetroHSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let curve: Double
    let onEditing: (String?) -> Void

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String,
         curve: Double = 1, onEditing: @escaping (String?) -> Void) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.curve = curve
        self.onEditing = onEditing
    }

    private var position: Double {
        let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return pow(min(max(fraction, 0), 1), 1 / curve)
    }

    private var valueLabel: String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(step == 1 ? 0 : 1))
        return "\(value.formatted(format)) \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geometry in
                let knob: CGFloat = 14
                let travel = geometry.size.width - knob
                ZStack(alignment: .leading) {
                    groove
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(LinearGradient(colors: [Color(white: 0.90), Color(white: 0.56)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay { Rectangle().fill(Color.black.opacity(0.55)).frame(width: 1, height: 6) }
                        .overlay { RetroBevel(raised: true) }
                        .overlay {
                            RoundedRectangle(cornerRadius: 1.5).strokeBorder(.black.opacity(0.8), lineWidth: 0.6)
                        }
                        .frame(width: knob, height: 11)
                        .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                        .offset(x: CGFloat(position) * travel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            setPosition(Double((drag.location.x - knob / 2) / max(travel, 1)))
                            onEditing("\(title): \(valueLabel)")
                        }
                        .onEnded { _ in onEditing(nil) }
                )
            }
            .frame(height: 12)
            Text(title)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .textCase(.uppercase)
                .foregroundStyle(RetroPalette.gold)
                .lineLimit(1)
                .fixedSize()
        }
        .help("\(title): \(valueLabel) · Ziehen zum Einstellen")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueLabel)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setValue(value + step)
            case .decrement: setValue(value - step)
            @unknown default: break
            }
        }
    }

    private var groove: some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        return shape
            .fill(Self.color(at: position))
            .overlay {
                shape.fill(LinearGradient(colors: [.white.opacity(0.30), .clear, .black.opacity(0.40)],
                                          startPoint: .top, endPoint: .bottom))
            }
            .overlay { Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1).padding(.horizontal, 3) }
            .overlay { shape.strokeBorder(.black.opacity(0.85), lineWidth: 1) }
            .frame(height: 7)
    }

    /// Green on the left, through yellow, to red on the right.
    private static func color(at position: Double) -> Color {
        let stops: [(Double, Double, Double)] = [(0.12, 0.80, 0.24), (0.95, 0.84, 0.16), (0.95, 0.26, 0.12)]
        let scaled = min(max(position, 0), 1) * 2
        let index = min(Int(scaled), 1)
        let t = scaled - Double(index)
        let a = stops[index]
        let b = stops[index + 1]
        return Color(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t)
    }

    private func setPosition(_ position: Double) {
        let fraction = pow(min(max(position, 0), 1), curve)
        setValue(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }

    private func setValue(_ candidate: Double) {
        let rounded = (candidate / step).rounded() * step
        let next = min(max(rounded, range.lowerBound), range.upperBound)
        if next != value { value = next }
    }
}

// MARK: - Chrome

private struct RetroTitleStrip: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        let label = [title, detail].compactMap { $0 }.joined(separator: " · ")
        HStack(spacing: 7) {
            stripes
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.6)
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(RetroPalette.gold)
                .layoutPriority(1)
            stripes
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isHeader)
    }

    private var stripes: some View {
        Canvas { context, size in
            for line in 0..<3 {
                let y = 1.5 + CGFloat(line) * 3
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(RetroPalette.gold.opacity(0.55)))
                context.fill(Path(CGRect(x: 0, y: y + 1, width: size.width, height: 1)),
                             with: .color(.black.opacity(0.55)))
            }
        }
        .frame(minWidth: 12, maxWidth: .infinity)
        .frame(height: 10)
    }
}

struct RetroBevel: View {
    let raised: Bool

    var body: some View {
        let light = Color.white.opacity(raised ? 0.30 : 0.10)
        let dark = Color.black.opacity(raised ? 0.65 : 0.80)
        ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(raised ? light : dark).frame(height: 1)
                Spacer(minLength: 0)
                Rectangle().fill(raised ? dark : light).frame(height: 1)
            }
            HStack(spacing: 0) {
                Rectangle().fill(raised ? light : dark).frame(width: 1)
                Spacer(minLength: 0)
                Rectangle().fill(raised ? dark : light).frame(width: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RetroButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: compact ? 9 : 10, weight: .black, design: .monospaced))
            .foregroundStyle(Color(white: isEnabled ? 0.10 : 0.42))
            .padding(.horizontal, compact ? 5 : 7)
            .frame(minWidth: 30, minHeight: compact ? 16 : 21)
            .background {
                LinearGradient(colors: pressed ? [Color(white: 0.52), Color(white: 0.68)]
                                               : [Color(white: 0.80), Color(white: 0.58)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay { RetroBevel(raised: !pressed) }
            .overlay { Rectangle().strokeBorder(.black.opacity(0.85), lineWidth: 1).padding(-1) }
            .offset(y: pressed ? 0.5 : 0)
            .contentShape(Rectangle())
    }
}

private extension View {
    func retroPanel() -> some View {
        background {
            LinearGradient(colors: [RetroPalette.panelTop, RetroPalette.panelBottom],
                           startPoint: .top, endPoint: .bottom)
        }
        .overlay { RetroBevel(raised: true) }
        .overlay { Rectangle().strokeBorder(.black.opacity(0.9), lineWidth: 1).padding(-1) }
    }

    func retroInset() -> some View {
        background(RetroPalette.lcd)
            .overlay { RetroBevel(raised: false) }
    }
}
