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
                List(player.files, id: \.self) { file in
                    jingleRow(file)
                }
                .listStyle(.bordered)
            }
            HStack(spacing: 12) {
                Button {
                    player.play()
                } label: {
                    Label("Abspielen", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!player.canPlay)
                Button(action: player.pause) {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(!player.canPause)
                Button(action: player.stop) {
                    Label("Stopp", systemImage: "stop.fill")
                }
                .disabled(!player.canStop)
                if let name = player.currentFilename {
                    Text(name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .controlSize(.large)
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
        return HStack(spacing: 12) {
            Button {
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
            Button {
                player.copyStreamDeckLink(for: name)
            } label: {
                Label("Link kopieren", systemImage: "link")
            }
            .help("Stream-Deck-Link für „\(name)“ kopieren")
            .accessibilityLabel("Stream-Deck-Link für „\(name)“ kopieren")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 3)
    }
}
