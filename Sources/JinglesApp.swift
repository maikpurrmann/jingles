import AppKit
import SwiftUI

private enum JinglesAppearance: String, CaseIterable, Identifiable {
    case standard, studio, retro

    var id: Self { self }
    var title: String {
        switch self {
        case .standard: "Standard"
        case .studio: "Studio"
        case .retro: "Retro"
        }
    }
}

private struct AppearancePicker: View {
    @Binding var appearance: JinglesAppearance

    var body: some View {
        Picker("Darstellung", selection: $appearance) {
            ForEach(JinglesAppearance.allCases) { option in
                Text(option.title).tag(option)
            }
        }
    }
}

@main
struct JinglesApp: App {
    @NSApplicationDelegateAdaptor(JinglesApplicationDelegate.self) private var applicationDelegate
    @StateObject private var player = JinglePlayer()
    @AppStorage("jinglesAppearance") private var appearance = JinglesAppearance.standard

    var body: some Scene {
        Window(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Jingles", id: "player") {
            JinglesView(player: player, appearance: appearance)
                .preferredColorScheme(appearance == .standard ? nil : .dark)
        }
        .defaultSize(width: 620, height: 470)
        // Retro has a fixed width like the old players, so the window follows its content size.
        .windowResizability(appearance == .retro ? .contentSize : .contentMinSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Divider()
                AppearancePicker(appearance: $appearance)
                    .pickerStyle(.inline)
            }
            CommandMenu("Stream Deck") {
                Button("Link für ausgewählten Jingle kopieren") {
                    if let filename = player.selectedFilename {
                        player.copyStreamDeckLink(for: filename)
                    }
                }
                .disabled(!player.files.contains { $0.lastPathComponent == player.selectedFilename })

                Button("Fade-Link kopieren", action: player.copyFadeLink)
            }
        }
    }
}

private final class JinglesApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let application = notification.object as? NSApplication,
              let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else { return }
        application.applicationIconImage = icon
    }
}

private struct JinglesView: View {
    @ObservedObject var player: JinglePlayer
    let appearance: JinglesAppearance
    @StateObject private var popovers = PopoverPresentation()

    private var isStudio: Bool { appearance == .studio }

    var body: some View {
        if appearance == .retro {
            RetroPlayerView(player: player)
        } else {
            panelBody
        }
    }

    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if isStudio {
                    StudioNameplate(folder: player.folder)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Jingles")
                            .font(.system(size: 30, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text(player.folder?.lastPathComponent ?? "Kein Ordner ausgewählt")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(player.folder?.path ?? "")
                    }
                }
                Spacer()
                Button(action: player.refresh) {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .help("Ordner aktualisieren")
                .disabled(player.folder == nil)
                Button(action: player.chooseFolder) {
                    Label("Ordner auswählen", systemImage: "folder")
                }
                .help("Ordner auswählen")
                Button {
                    popovers.showsInfo.toggle()
                } label: {
                    Label("Info und Bedienhilfe", systemImage: "info.circle")
                }
                .help("Info und Bedienhilfe")
                .popover(isPresented: $popovers.showsInfo, arrowEdge: .bottom) {
                    JinglesInfoView()
                }
            }
            .labelStyle(.iconOnly)
            if player.files.isEmpty {
                Spacer(minLength: 40)
                Text(player.folder == nil
                     ? "Wähle einen Ordner mit WAV- oder MP3-Dateien."
                     : "In diesem Ordner sind keine WAV- oder MP3-Dateien.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 40)
            } else if isStudio {
                studioList
            } else {
                List(player.files, id: \.self, selection: Binding(
                    get: { player.selectedFilename },
                    set: { player.select($0) }
                )) { file in
                    jingleRow(file)
                        .tag(file.lastPathComponent)
                }
                .listStyle(.bordered)
            }
            if isStudio {
                StudioConsole(player: player)
            } else {
                standardConsole
            }
            if let message = player.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let error = player.playbackError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let error = player.remoteError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, isStudio ? 34 : 22)
        .frame(minWidth: isStudio ? 590 : 500, minHeight: isStudio ? 390 : 330)
        .background {
            if isStudio {
                StudioCase()
            }
        }
    }

    private var standardConsole: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                transportControls
                Spacer(minLength: 0)
                playbackClock
                Spacer(minLength: 0)
                fadeControls
            }
            .labelStyle(.iconOnly)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            PlaybackProgressBar(
                progress: player.playbackProgress,
                duration: player.playbackDuration,
                run: player.canPause ? player.playbackRun : nil
            )
            .frame(maxWidth: .infinity)
            .frame(height: 7)
            .background(.quaternary, in: Capsule())
            .clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Wiedergabefortschritt")
            .accessibilityValue("\(Int(player.playbackProgress * 100)) Prozent")
        }
    }

    private var playbackClock: some View {
        let paused = player.canStop && !player.canPause
        return VStack(spacing: 0) {
            Text(paused ? "Restzeit · Pausiert" : "Restzeit")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(timeLabel(player.remainingSeconds ?? 0))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(player.remainingSeconds == nil ? .secondary : .primary)
        }
        .frame(minWidth: 108)
        .accessibilityElement(children: .combine)
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            Button {
                player.play()
            } label: {
                Label("Abspielen", systemImage: "play.fill")
            }
            .buttonStyle(TransportButtonStyle(prominent: true))
            .help("Abspielen")
            .disabled(!player.canPlay)
            Button(action: player.pause) {
                Label("Pause", systemImage: "pause.fill")
            }
            .buttonStyle(TransportButtonStyle())
            .help("Pause")
            .disabled(!player.canPause)
            Button(action: player.stop) {
                Label("Stopp", systemImage: "stop.fill")
            }
            .buttonStyle(TransportButtonStyle())
            .help("Stopp")
            .disabled(!player.canStop)
        }
    }

    private var fadeControls: some View {
        let level = player.isLowered ? player.loweredPercent : 100
        let state = player.isLowered ? "Abgesenkt" : "Normal"
        let action = player.isLowered ? "Auf 100 % anheben" : "Auf \(player.loweredPercent) % absenken"
        return HStack(spacing: 6) {
            Button {
                player.toggleFade()
            } label: {
                Label {
                    Text("\(state) · \(level) %").monospacedDigit()
                } icon: {
                    Image(systemName: player.isLowered ? "speaker.wave.1" : "speaker.wave.2")
                }
                .labelStyle(.titleAndIcon)
                .fixedSize()
            }
            .buttonStyle(.bordered)
            .foregroundStyle(player.isLowered ? Color.orange : Color.primary)
            .help(action)
            .accessibilityLabel(action)
            .accessibilityValue("\(state), \(level) Prozent")

            fadeSettingsButton
        }
        .controlSize(.regular)
    }

    private var fadeSettingsButton: some View {
        Button {
            popovers.showsFadeSettings.toggle()
        } label: {
            Label("Fade-Einstellungen", systemImage: "slider.horizontal.3")
        }
        .help("Fade-Einstellungen")
        .popover(isPresented: $popovers.showsFadeSettings, arrowEdge: .top) {
            fadeSettings
        }
    }

    private var fadeSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jingle-Fade").font(.headline)
            Stepper(value: $player.loweredPercent, in: 0...100) {
                LabeledContent("Absenken auf", value: "\(player.loweredPercent) %")
            }
            Stepper(value: $player.fadeDownSeconds, in: 0...30, step: 0.1) {
                LabeledContent("Zeit zum Absenken", value: fadeTimeLabel(player.fadeDownSeconds))
            }
            Stepper(value: $player.fadeUpSeconds, in: 0...30, step: 0.1) {
                LabeledContent("Zeit zum Anheben", value: fadeTimeLabel(player.fadeUpSeconds))
            }
        }
        .controlSize(.regular)
        .padding(16)
        .frame(width: 320)
    }

    private func fadeTimeLabel(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    private var studioList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(player.files, id: \.self) { file in
                    let selected = file.lastPathComponent == player.selectedFilename
                    jingleRow(file)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selected ? StudioPalette.amber.opacity(0.15) : .clear)
                        .overlay(alignment: .leading) {
                            if selected {
                                Rectangle().fill(StudioPalette.amber).frame(width: 2)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(StudioPalette.cream.opacity(0.09)).frame(height: 1)
                        }
                }
            }
        }
        .background(Color(white: 0.095))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5).strokeBorder(StudioPalette.cream.opacity(0.20))
                .allowsHitTesting(false)
        }
    }

    private func jingleRow(_ file: URL) -> some View {
        let name = file.lastPathComponent
        let remaining = name == player.currentFilename ? player.remainingSeconds : nil
        let isPlaying = remaining != nil && player.canPause
        let playingColor = isStudio ? StudioPalette.amber : Color.mint
        let timeColor: Color = if name == player.selectedFilename {
            .primary
        } else if remaining != nil {
            .accentColor
        } else {
            .secondary
        }
        return HStack(spacing: 12) {
            Button {
                player.select(name)
                player.play(named: name)
            } label: {
                Image(systemName: "play.fill")
                    .foregroundStyle(isPlaying ? playingColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(playingColor.opacity(isPlaying ? 0.16 : 0), in: Circle())
                    .contentShape(Rectangle())
            }
            .help("„\(name)“ von Anfang an abspielen")
            .accessibilityLabel("„\(name)“ abspielen")
            if isStudio {
                Button {
                    player.select(name)
                } label: {
                    jingleRowDetails(name, file: file, remaining: remaining, isPlaying: isPlaying,
                                     playingColor: playingColor, timeColor: timeColor)
                        .contentShape(Rectangle())
                        .frame(minHeight: 24)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(name == player.selectedFilename ? .isSelected : [])
            } else {
                jingleRowDetails(name, file: file, remaining: remaining, isPlaying: isPlaying,
                                 playingColor: playingColor, timeColor: timeColor)
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 3)
    }

    private func jingleRowDetails(_ name: String, file: URL, remaining: Int?, isPlaying: Bool,
                                  playingColor: Color, timeColor: Color) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(name)
            Spacer()
            Image(systemName: "waveform")
                .foregroundStyle(playingColor)
                .opacity(isPlaying ? 1 : 0)
                .accessibilityHidden(true)
            Text(timeLabel(remaining ?? player.durations[file]))
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .frame(minWidth: 42, alignment: .trailing)
                .accessibilityLabel(isPlaying ? "Läuft, Restzeit" : remaining == nil ? "Dauer" : "Restzeit")
                .accessibilityValue(timeLabel(remaining ?? player.durations[file]))
        }
    }

    private func timeLabel(_ seconds: Int?) -> String {
        guard let seconds else { return "–:––" }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

struct JinglesInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Über \(appName)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Version \(version) · Build \(build)")
                if let date = Bundle.main.object(forInfoDictionaryKey: "JinglesBuildDate") as? String {
                    Text("Gebaut am \(date)")
                }
                Text("Für Planlosgelöst entwickelt, seit November 2026.")
            }
            .foregroundStyle(.secondary)
            .font(.callout)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Stream Deck").font(.headline)
                Text("Installiere das Jingles-Plugin und lege Jingle, Fade oder Restzeit auf eine Taste. Bei Jingle wählst du anschließend die Datei. Die Tasten zeigen den Zustand der geöffneten App an.")
                Link("Plugin und Anleitung",
                     destination: URL(string: "https://github.com/maikpurrmann/jingles#stream-deck")!)
                Text("Die bisherigen Steuerlinks findest du im Menü „Stream Deck“.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Einspieler").font(.headline)
                Text("Wähle einen Ordner mit WAV- oder MP3-Dateien. Ein Klick auf die Zeile wählt den Jingle vor. Das Play-Symbol in der Zeile startet ihn von vorn.")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Wiedergabe und Fade").font(.headline)
                Text("Pause hält die Position, Stopp setzt sie zurück. Der Prozentknopf senkt alle Jingles gemeinsam ab und hebt sie beim nächsten Klick wieder an. Zielpegel und Zeiten stehen in den Fade-Einstellungen.")
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .frame(width: 350)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Jingles"
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}

private struct TransportButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let color = prominent && isEnabled ? Color.accentColor : Color.primary
        return configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color.opacity(isEnabled ? 1 : 0.35))
            .frame(width: 44, height: 44)
            .background(color.opacity(isEnabled ? 0.14 : 0.06), in: Circle())
            .overlay {
                Circle().strokeBorder(color.opacity(isEnabled ? 0.30 : 0.10), lineWidth: 1)
            }
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private final class PopoverPresentation: ObservableObject {
    @Published var showsInfo = false
    @Published var showsFadeSettings = false
}
