import AppKit
import AVFoundation
import SwiftUI

final class JinglePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private enum PlaybackState {
        case stopped, playing, paused
    }

    @Published private(set) var folder: URL?
    @Published private(set) var files: [URL] = []
    @Published private(set) var durations: [URL: Int] = [:]
    @Published private(set) var currentFilename: String?
    @Published private(set) var remainingSeconds: Int?
    @Published private(set) var playbackProgress = 0.0
    @Published private var nextFilename: String?
    @Published private var state: PlaybackState = .stopped
    @Published private(set) var message: String?
    @Published private(set) var playbackError: String?
    @Published private(set) var remoteError: String?

    var selectedFilename: String? { nextFilename ?? currentFilename ?? files.first?.lastPathComponent }
    var canPlay: Bool {
        guard let selectedFilename else { return false }
        return state != .playing || selectedFilename != currentFilename
    }
    var canPause: Bool { state == .playing }
    var canStop: Bool { state != .stopped }

    private let folderKey = "jingleFolderPath"
    private let filenameKey = "lastJingleFilename"
    private let defaults: UserDefaults
    private let remote = StreamDeckControl()
    private var audio: AVAudioPlayer?
    private var durationTask: Task<Void, Never>?
    private var countdownTimer: Timer?

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
            case .play(let name): return self.toggle(named: name)
            }
        }, failed: { [weak self] message in
            self?.remoteError = message
        })
    }

    deinit {
        durationTask?.cancel()
        countdownTimer?.invalidate()
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
                nextFilename = nil
                defaults.removeObject(forKey: filenameKey)
            }
            folder = url
            updateCatalog(contents, reloadDurations: true)
            defaults.set(url.path, forKey: folderKey)
            message = nil
            playbackError = nil
        } catch {
            playbackError = "Der Ordner „\(url.lastPathComponent)“ konnte nicht gelesen werden."
        }
    }

    func refresh() {
        refreshCatalog(reloadDurations: true)
    }

    private func refreshCatalog(reloadDurations: Bool = false) {
        message = nil
        guard let folder else { return }
        do {
            updateCatalog(try listAudioFiles(in: folder), reloadDurations: reloadDurations)
            playbackError = nil
        } catch {
            updateCatalog([])
            playbackError = "Der Ordner „\(folder.lastPathComponent)“ konnte nicht gelesen werden."
        }
    }

    func toggle() -> PlaybackResult {
        if canPause {
            pause()
            return .paused
        }
        return playCurrent()
    }

    func select(_ filename: String?) {
        nextFilename = filename == currentFilename ? nil : filename
    }

    @discardableResult
    func play() -> PlaybackResult {
        if let nextFilename {
            return play(named: nextFilename)
        }
        return playCurrent()
    }

    private func playCurrent() -> PlaybackResult {
        if canPause { return .playing }
        if let audio {
            return resume(audio)
        }
        if let currentFilename {
            return play(named: currentFilename)
        }
        refreshCatalog()
        guard let first = files.first else { return .noFile }
        return play(named: first.lastPathComponent)
    }

    func pause() {
        guard canPause, let audio else { return }
        audio.pause()
        countdownTimer?.invalidate()
        countdownTimer = nil
        updatePlaybackTime()
        state = .paused
    }

    func stop() {
        clearPlayback()
        playbackError = nil
    }

    private func toggle(named name: String) -> PlaybackResult {
        if canPause, currentFilename == name {
            stop()
            return .stopped
        }
        return play(named: name)
    }

    @discardableResult
    func play(named name: String) -> PlaybackResult {
        refreshCatalog()
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
            if nextFilename == currentFilename { nextFilename = nil }
            defaults.set(currentFilename, forKey: filenameKey)
            durations[file] = Self.displaySeconds(next.duration)
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
        guard player.play() else {
            clearPlayback()
            playbackError = "Die Wiedergabe konnte nicht gestartet werden."
            return .unavailable
        }
        state = .playing
        playbackError = nil
        updatePlaybackTime()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePlaybackTime()
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
        return .playing
    }

    private func clearPlayback() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        audio?.delegate = nil
        audio?.stop()
        audio = nil
        remainingSeconds = nil
        playbackProgress = 0
        state = .stopped
    }

    private func updatePlaybackTime() {
        guard let audio else { return }
        let duration = audio.duration
        let elapsed = audio.currentTime
        let remaining = Self.displaySeconds(max(0, duration - elapsed))
        if remainingSeconds != remaining {
            remainingSeconds = remaining
        }
        let progress = duration.isFinite && duration > 0 ? min(max(0, elapsed / duration), 1) : 0
        if playbackProgress != progress {
            playbackProgress = progress
        }
    }

    private func updateCatalog(_ contents: [URL], reloadDurations: Bool = false) {
        guard reloadDurations || files != contents else { return }
        files = contents
        if let nextFilename, !contents.contains(where: { $0.lastPathComponent == nextFilename }) {
            self.nextFilename = nil
        }
        let presentFiles = Set(contents)
        durations = durations.filter { presentFiles.contains($0.key) }
        durationTask?.cancel()
        durationTask = Task { @MainActor [weak self] in
            for file in contents {
                guard !Task.isCancelled else { return }
                let asset = AVURLAsset(url: file)
                let duration = try? await asset.load(.duration)
                guard !Task.isCancelled else { return }
                self?.durations[file] = duration.flatMap { Self.displaySeconds($0.seconds) }
            }
        }
    }

    private static func displaySeconds(_ time: TimeInterval) -> Int? {
        guard time.isFinite, time >= 0 else { return nil }
        return Int(exactly: time.rounded(.up))
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
