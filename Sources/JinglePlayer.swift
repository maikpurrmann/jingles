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
    @Published private var nextFilename: String?
    @Published private var state: PlaybackState = .stopped
    @Published private(set) var message: String?
    @Published private(set) var playbackError: String?
    @Published private(set) var remoteError: String?
    @Published private(set) var isLowered = false
    @Published var loweredPercent = 10 {
        didSet {
            defaults.set(loweredPercent, forKey: "loweredPercent")
            if isLowered {
                setMasterLevel(Float(loweredPercent) / 100, duration: fadeDownSeconds)
            }
        }
    }
    @Published var fadeDownSeconds = 0.3 {
        didSet { defaults.set(fadeDownSeconds, forKey: "fadeDownSeconds") }
    }
    @Published var fadeUpSeconds = 3.0 {
        didSet { defaults.set(fadeUpSeconds, forKey: "fadeUpSeconds") }
    }

    var selectedFilename: String? { nextFilename ?? currentFilename ?? files.first?.lastPathComponent }
    var canPlay: Bool {
        guard let selectedFilename else { return false }
        return state != .playing || selectedFilename != currentFilename
    }
    var canPause: Bool { state == .playing }
    var canStop: Bool { state != .stopped }
    var playbackDuration: TimeInterval { audio?.duration ?? 0 }
    var playbackProgress: Double {
        guard let audio, audio.duration.isFinite, audio.duration > 0 else { return 0 }
        let elapsed = audio.currentTime
        guard elapsed.isFinite else { return 0 }
        return min(max(0, elapsed / audio.duration), 1)
    }

    private let folderKey = "jingleFolderPath"
    private let filenameKey = "lastJingleFilename"
    private let defaults: UserDefaults
    private let remote = StreamDeckControl()
    private var audio: AVAudioPlayer?
    private var durationTask: Task<Void, Never>?
    private var countdownTimer: Timer?
    private(set) var playbackRun = UInt64(0)
    private var masterRamp = MasterGainRamp(start: 1, target: 1, beginsAt: 0, duration: 0)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        defaults.register(defaults: ["loweredPercent": 10, "fadeDownSeconds": 0.3, "fadeUpSeconds": 3.0])
        loweredPercent = min(max(defaults.integer(forKey: "loweredPercent"), 0), 100)
        fadeDownSeconds = Self.checkedDuration(defaults.double(forKey: "fadeDownSeconds"), fallback: 0.3)
        fadeUpSeconds = Self.checkedDuration(defaults.double(forKey: "fadeUpSeconds"), fallback: 3.0)
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
            guard let self else { return .init(status: "503 Service Unavailable", text: "playback unavailable") }
            return self.handleStreamDeckCommand(command)
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
        updateRemainingTime()
        state = .paused
    }

    func stop() {
        clearPlayback()
        playbackError = nil
    }

    @discardableResult
    func toggleFade() -> PlaybackResult {
        isLowered.toggle()
        let target: Float = isLowered ? Float(loweredPercent) / 100 : 1
        setMasterLevel(target, duration: isLowered ? fadeDownSeconds : fadeUpSeconds)
        return isLowered ? .lowered : .normal
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

    private func handleStreamDeckCommand(_ command: StreamDeckCommand) -> StreamDeckResponse {
        let result: PlaybackResult
        switch command {
        case .status:
            let playingFilename = state == .playing ? currentFilename : nil
            let playingRemainingSeconds = state == .playing ? remainingSeconds : nil
            return .init(json: [
                "playingFilename": playingFilename.map { $0 as Any } ?? NSNull(),
                "isLowered": isLowered,
                "remainingSeconds": playingRemainingSeconds.map { $0 as Any } ?? NSNull()
            ])
        case .jingles:
            return .init(json: ["filenames": files.map(\.lastPathComponent)])
        case .toggle:
            result = toggle()
        case .play(let name):
            result = toggle(named: name)
        case .fade:
            result = toggleFade()
        }
        let response = result.response
        return .init(status: response.status, text: response.body)
    }

    func copyStreamDeckLink(for name: String) {
        copyLink(.play(name), message: "Stream-Deck-Link für „\(name)“ kopiert.")
    }

    func copyFadeLink() {
        copyLink(.fade, message: "Stream-Deck-Link für den Fade kopiert.")
    }

    private func copyLink(_ command: StreamDeckCommand, message: String) {
        guard let link = command.link else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(link, forType: .string) {
            self.message = message
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
        let now = ProcessInfo.processInfo.systemUptime
        player.setVolume(masterRamp.level(at: now), fadeDuration: 0)
        guard player.play() else {
            clearPlayback()
            playbackError = "Die Wiedergabe konnte nicht gestartet werden."
            return .unavailable
        }
        continueMasterRamp(on: player, at: now)
        playbackRun &+= 1
        state = .playing
        playbackError = nil
        updateRemainingTime()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateRemainingTime()
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
        state = .stopped
    }

    private func setMasterLevel(_ target: Float, duration: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        masterRamp = MasterGainRamp(start: masterRamp.level(at: now), target: target,
                                    beginsAt: now, duration: duration)
        guard let audio, canPause else { return }
        audio.setVolume(masterRamp.level(at: now), fadeDuration: 0)
        continueMasterRamp(on: audio, at: now)
    }

    private func continueMasterRamp(on audio: AVAudioPlayer, at time: TimeInterval) {
        let remaining = masterRamp.remaining(at: time)
        if remaining > 0 {
            audio.setVolume(masterRamp.target, fadeDuration: remaining)
        }
    }

    private static func checkedDuration(_ seconds: Double, fallback: Double) -> Double {
        seconds.isFinite ? min(max(seconds, 0), 30) : fallback
    }

    private func updateRemainingTime() {
        guard let audio else { return }
        let remaining = Self.displaySeconds(max(0, audio.duration - audio.currentTime))
        if remainingSeconds != remaining {
            remainingSeconds = remaining
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

private struct MasterGainRamp {
    let start: Float
    let target: Float
    let beginsAt: TimeInterval
    let duration: TimeInterval

    func level(at time: TimeInterval) -> Float {
        guard duration > 0 else { return target }
        let position = Float(1 - remaining(at: time) / duration)
        return start + (target - start) * position
    }

    func remaining(at time: TimeInterval) -> TimeInterval {
        max(0, duration - max(0, time - beginsAt))
    }
}
