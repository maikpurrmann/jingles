import AppKit
import SwiftUI

@main
struct JinglesApp: App {
    @NSApplicationDelegateAdaptor(JinglesApplicationDelegate.self) private var applicationDelegate
    @StateObject private var player = JinglePlayer()

    var body: some Scene {
        Window("Jingles", id: "player") {
            JinglesView(player: player)
        }
        .defaultSize(width: 620, height: 470)
        .windowResizability(.contentMinSize)
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
    @StateObject private var fadeSettingsPresentation = FadeSettingsPresentation()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                playbackClock
                Spacer()
                HStack(spacing: 8) {
                    Text(player.folder?.lastPathComponent ?? "Kein Ordner ausgewählt")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(player.folder?.path ?? "")
                    Button(action: player.refresh) {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
                    .help("Ordner aktualisieren")
                    .disabled(player.folder == nil)
                    Button(action: player.chooseFolder) {
                        Label("Ordner auswählen", systemImage: "folder")
                    }
                    .help("Ordner auswählen")
                }
                .labelStyle(.iconOnly)
            }
            if player.files.isEmpty {
                Spacer(minLength: 40)
                Text(player.folder == nil
                     ? "Wähle einen Ordner mit WAV- oder MP3-Dateien."
                     : "In diesem Ordner sind keine WAV- oder MP3-Dateien.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 40)
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
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        player.play()
                    } label: {
                        Label("Abspielen", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
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
        .padding(22)
        .frame(minWidth: 500, minHeight: 330)
    }

    private var playbackClock: some View {
        let paused = player.canStop && !player.canPause
        return VStack(alignment: .leading, spacing: 2) {
            Text(paused ? "Restzeit · Pausiert" : "Restzeit")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(timeLabel(player.remainingSeconds))
                .font(.system(size: 38, weight: .semibold, design: .monospaced))
                .foregroundStyle(player.remainingSeconds == nil ? .secondary : .primary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
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

            Button {
                fadeSettingsPresentation.isOpen.toggle()
            } label: {
                Label("Fade-Einstellungen", systemImage: "slider.horizontal.3")
            }
            .help("Fade-Einstellungen")
            .popover(isPresented: $fadeSettingsPresentation.isOpen, arrowEdge: .top) {
                fadeSettings
            }
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
            Button {
                player.copyFadeLink()
                fadeSettingsPresentation.isOpen = false
            } label: {
                Label("Stream-Deck-Link kopieren", systemImage: "link")
                    .labelStyle(.titleAndIcon)
            }
        }
        .controlSize(.regular)
        .padding(16)
        .frame(width: 320)
    }

    private func fadeTimeLabel(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    private func jingleRow(_ file: URL) -> some View {
        let name = file.lastPathComponent
        let remaining = name == player.currentFilename ? player.remainingSeconds : nil
        let isPlaying = remaining != nil && player.canPause
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
                    .foregroundStyle(isPlaying ? Color.mint : Color.secondary)
            }
            .help("„\(name)“ von Anfang an abspielen")
            .accessibilityLabel("„\(name)“ abspielen")
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(name)
            Spacer()
            Image(systemName: "waveform")
                .foregroundStyle(Color.mint)
                .opacity(isPlaying ? 1 : 0)
                .accessibilityHidden(true)
            Text(timeLabel(remaining ?? player.durations[file]))
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .frame(minWidth: 42, alignment: .trailing)
                .accessibilityLabel(isPlaying ? "Läuft, Restzeit" : remaining == nil ? "Dauer" : "Restzeit")
                .accessibilityValue(timeLabel(remaining ?? player.durations[file]))
            Button {
                player.copyStreamDeckLink(for: name)
            } label: {
                Label("Link kopieren", systemImage: "link")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .help("Stream-Deck-Link für „\(name)“ kopieren")
            .accessibilityLabel("Stream-Deck-Link für „\(name)“ kopieren")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 3)
    }

    private func timeLabel(_ seconds: Int?) -> String {
        guard let seconds else { return "–:––" }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private final class FadeSettingsPresentation: ObservableObject {
    @Published var isOpen = false
}
