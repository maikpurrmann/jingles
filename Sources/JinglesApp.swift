import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@main
struct JinglesApp: App {
    @StateObject private var player = JinglePlayer()

    var body: some Scene {
        Window("Jingles", id: "player") {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Jingles")
                        .font(.system(size: 32, weight: .semibold))
                    Text(player.filename ?? "Keine WAV ausgewählt")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(player.filename ?? "")
                }
                HStack(spacing: 12) {
                    Button {
                        player.toggle()
                    } label: {
                        Label(player.isPlaying ? "Pause" : "Abspielen",
                              systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(minWidth: 95)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(player.filename == nil)
                    Button("WAV auswählen …", action: player.chooseFile)
                        .controlSize(.large)
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
            .padding(26)
            .frame(width: 360, alignment: .leading)
        }
        .windowResizability(.contentSize)
    }
}

final class JinglePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var filename: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackError: String?
    @Published private(set) var remoteError: String?

    private let fileKey = "wavePath"
    private let remote = StreamDeckControl()
    private var audio: AVAudioPlayer?

    override init() {
        super.init()
        if let path = UserDefaults.standard.string(forKey: fileKey) {
            load(URL(fileURLWithPath: path))
        }
        remote.start(toggle: { [weak self] in
            self?.toggle() ?? .unavailable
        }, failed: { [weak self] message in
            self?.remoteError = message
        })
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            load(url)
        }
    }

    private func load(_ url: URL) {
        do {
            let next = try AVAudioPlayer(contentsOf: url)
            next.delegate = self
            audio?.stop()
            audio = next
            isPlaying = false
            filename = url.lastPathComponent
            playbackError = nil
            UserDefaults.standard.set(url.path, forKey: fileKey)
        } catch {
            playbackError = "Die WAV „\(url.lastPathComponent)“ konnte nicht geöffnet werden."
        }
    }

    @discardableResult
    func toggle() -> PlaybackResult {
        guard let audio else { return .noFile }
        if audio.isPlaying {
            audio.pause()
            isPlaying = false
            return .paused
        }
        isPlaying = audio.play()
        playbackError = isPlaying ? nil : "Die Wiedergabe konnte nicht gestartet werden."
        return isPlaying ? .playing : .unavailable
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audio else { return }
        player.currentTime = 0
        isPlaying = false
        if !flag {
            playbackError = "Die Wiedergabe wurde unterbrochen."
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === audio else { return }
        isPlaying = false
        playbackError = "Die WAV konnte nicht fertig abgespielt werden."
    }
}
