import AppKit
import AVFoundation
import SwiftUI

final class JinglePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var folder: URL?
    @Published private(set) var files: [URL] = []
    @Published private(set) var currentFilename: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var message: String?
    @Published private(set) var playbackError: String?
    @Published private(set) var remoteError: String?

    var canToggle: Bool { currentFilename != nil || !files.isEmpty }

    private let folderKey = "jingleFolderPath"
    private let filenameKey = "lastJingleFilename"
    private let defaults: UserDefaults
    private let remote = StreamDeckControl()
    private var audio: AVAudioPlayer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        if let path = defaults.string(forKey: folderKey) {
            folder = URL(fileURLWithPath: path, isDirectory: true)
            currentFilename = defaults.string(forKey: filenameKey)
        } else if let path = defaults.string(forKey: "wavePath") {
            let previousFile = URL(fileURLWithPath: path)
            folder = previousFile.deletingLastPathComponent()
            currentFilename = previousFile.lastPathComponent
            defaults.set(folder?.path, forKey: folderKey)
            defaults.set(currentFilename, forKey: filenameKey)
        }
        refresh()
        remote.start(handle: { [weak self] command in
            guard let self else { return .unavailable }
            switch command {
            case .toggle: return self.toggle()
            case .play(let name): return self.play(named: name)
            }
        }, failed: { [weak self] message in
            self?.remoteError = message
        })
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let contents = try listAudioFiles(in: url)
            if folder?.standardizedFileURL != url.standardizedFileURL {
                clearPlayback()
                currentFilename = nil
                defaults.removeObject(forKey: filenameKey)
            }
            folder = url
            files = contents
            defaults.set(url.path, forKey: folderKey)
            message = nil
            playbackError = nil
        } catch {
            playbackError = "Der Ordner „\(url.lastPathComponent)“ konnte nicht gelesen werden."
        }
    }

    func refresh() {
        message = nil
        guard let folder else { return }
        do {
            files = try listAudioFiles(in: folder)
            playbackError = nil
        } catch {
            files = []
            playbackError = "Der Ordner „\(folder.lastPathComponent)“ konnte nicht gelesen werden."
        }
    }

    @discardableResult
    func toggle() -> PlaybackResult {
        if let audio {
            if audio.isPlaying {
                audio.pause()
                isPlaying = false
                return .paused
            }
            return resume(audio)
        }
        if let currentFilename {
            return play(named: currentFilename)
        }
        refresh()
        guard let first = files.first else { return .noFile }
        return play(named: first.lastPathComponent)
    }

    @discardableResult
    func play(named name: String) -> PlaybackResult {
        refresh()
        guard folder != nil else { return .noFile }
        if playbackError != nil { return .unavailable }
        guard let file = files.first(where: { $0.lastPathComponent == name }) else {
            playbackError = "Die Datei „\(name)“ ist im ausgewählten Ordner nicht vorhanden."
            return .missingFile
        }

        do {
            let next = try AVAudioPlayer(contentsOf: file)
            next.delegate = self
            clearPlayback()
            currentFilename = file.lastPathComponent
            defaults.set(currentFilename, forKey: filenameKey)
            audio = next
            return resume(next)
        } catch {
            playbackError = "Die Datei „\(name)“ konnte nicht geöffnet werden."
            return .unavailable
        }
    }

    func copyStreamDeckLink(for name: String) {
        guard let link = StreamDeckCommand.play(name).link else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(link, forType: .string) {
            message = "Stream-Deck-Link für „\(name)“ kopiert."
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audio else { return }
        clearPlayback()
        if !flag {
            playbackError = "Die Wiedergabe wurde unterbrochen."
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === audio else { return }
        clearPlayback()
        playbackError = "Die Datei konnte nicht fertig abgespielt werden."
    }

    private func resume(_ player: AVAudioPlayer) -> PlaybackResult {
        isPlaying = player.play()
        playbackError = isPlaying ? nil : "Die Wiedergabe konnte nicht gestartet werden."
        return isPlaying ? .playing : .unavailable
    }

    private func clearPlayback() {
        audio?.delegate = nil
        audio?.stop()
        audio = nil
        isPlaying = false
    }

    private func listAudioFiles(in folder: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles
        )
        return contents.filter { file in
            let fileExtension = file.pathExtension.lowercased()
            guard fileExtension == "wav" || fileExtension == "mp3" else { return false }
            return (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { a, b in
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }
    }
}
