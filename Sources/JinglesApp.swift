import AppKit
import SwiftUI

@main
struct JinglesApp: App {
    @StateObject private var player = JinglePlayer()

    var body: some Scene {
        Window("Jingles", id: "player") {
            JinglesView(player: player)
        }
        .defaultSize(width: 620, height: 470)
        .windowResizability(.contentMinSize)
    }
}

private struct JinglesView: View {
    @ObservedObject var player: JinglePlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Jingles")
                        .font(.system(size: 32, weight: .semibold))
                    Text(player.folder?.lastPathComponent ?? "Kein Ordner ausgewählt")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(player.folder?.path ?? "")
                }
                Spacer()
                Button(action: player.refresh) {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Ordner aktualisieren")
                .disabled(player.folder == nil)
                Button("Ordner auswählen …", action: player.chooseFolder)
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
                    if let name = player.canStop ? player.currentFilename : player.selectedFilename {
                        Text(name)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let remaining = player.remainingSeconds {
                        Spacer(minLength: 0)
                        Text("Noch \(timeLabel(remaining))")
                            .monospacedDigit()
                            .fixedSize()
                    }
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

    private func jingleRow(_ file: URL) -> some View {
        let name = file.lastPathComponent
        let remaining = name == player.currentFilename ? player.remainingSeconds : nil
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
            }
            .help("„\(name)“ von Anfang an abspielen")
            .accessibilityLabel("„\(name)“ abspielen")
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(name)
            Spacer()
            Text(timeLabel(remaining ?? player.durations[file]))
                .monospacedDigit()
                .foregroundStyle(timeColor)
                .frame(minWidth: 42, alignment: .trailing)
                .accessibilityLabel(remaining == nil ? "Dauer" : "Restzeit")
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
