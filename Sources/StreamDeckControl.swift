import Foundation
import Network

enum PlaybackResult {
    case playing, paused, stopped, noFile, missingFile, unavailable

    var response: (status: String, body: String) {
        switch self {
        case .playing: ("200 OK", "playing")
        case .paused: ("200 OK", "paused")
        case .stopped: ("200 OK", "stopped")
        case .noFile: ("409 Conflict", "no jingle selected")
        case .missingFile: ("404 Not Found", "jingle not found")
        case .unavailable: ("503 Service Unavailable", "playback unavailable")
        }
    }
}

enum StreamDeckCommand {
    case toggle
    case play(String)

    static let host = "127.0.0.1"
    static let port: NWEndpoint.Port = 17639
    private static let playPrefix = "/play/"
    private static let filenameCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    init?(target: String) {
        if target == "/toggle" {
            self = .toggle
            return
        }
        guard target.hasPrefix(Self.playPrefix),
              let name = target.dropFirst(Self.playPrefix.count).removingPercentEncoding,
              !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            return nil
        }
        self = .play(name)
    }

    var link: String? {
        let root = "http://\(Self.host):\(Self.port)"
        switch self {
        case .toggle:
            return root + "/toggle"
        case .play(let name):
            guard let encoded = name.addingPercentEncoding(withAllowedCharacters: Self.filenameCharacters) else {
                return nil
            }
            return root + Self.playPrefix + encoded
        }
    }
}

// The listener runs on the main queue so local clicks and remote commands use the same player.
final class StreamDeckControl {
    private let headerEnd = Data([13, 10, 13, 10])
    private let maxHeaderBytes = 8192
    private var listener: NWListener?

    func start(handle: @escaping (StreamDeckCommand) -> PlaybackResult, failed: @escaping (String) -> Void) {
        let parameters = NWParameters.tcp
        let host = NWEndpoint.Host(StreamDeckCommand.host)
        let port = StreamDeckCommand.port
        parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    connection.cancel()
                    return
                }
                connection.start(queue: .main)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak connection] in
                    connection?.cancel()
                }
                self.readRequest(connection, bytes: Data(), handle: handle)
            }
            listener.stateUpdateHandler = { state in
                if case .failed = state {
                    failed("Stream Deck ist nicht erreichbar. Port \(port) prüfen.")
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            failed("Die Stream-Deck-Steuerung konnte nicht gestartet werden.")
        }
    }

    private func readRequest(_ connection: NWConnection, bytes: Data,
                             handle: @escaping (StreamDeckCommand) -> PlaybackResult) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: maxHeaderBytes - bytes.count) {
            [weak self] data, _, complete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            let received = bytes + (data ?? Data())
            if let end = received.range(of: self.headerEnd)?.lowerBound {
                self.handleRequest(connection, header: received.prefix(upTo: end), handle: handle)
            } else if complete || received.count >= self.maxHeaderBytes {
                self.reply(connection, status: "400 Bad Request", body: "invalid request")
            } else {
                self.readRequest(connection, bytes: received, handle: handle)
            }
        }
    }

    private func handleRequest(_ connection: NWConnection, header: Data,
                               handle: (StreamDeckCommand) -> PlaybackResult) {
        let lines = String(decoding: header, as: UTF8.self).components(separatedBy: "\r\n")
        let authority = "host: \(StreamDeckCommand.host):\(StreamDeckCommand.port)"
        guard let request = lines.first,
              lines.dropFirst().contains(where: { $0.lowercased() == authority }),
              !lines.dropFirst().contains(where: { $0.lowercased().hasPrefix("sec-fetch-site:") }) else {
            reply(connection, status: "400 Bad Request", body: "local control only")
            return
        }
        let parts = request.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "GET", parts[2] == "HTTP/1.1",
              let command = StreamDeckCommand(target: String(parts[1])) else {
            reply(connection, status: "404 Not Found", body: "unknown command")
            return
        }
        let result = handle(command).response
        reply(connection, status: result.status, body: result.body)
    }

    private func reply(_ connection: NWConnection, status: String, body: String) {
        let message = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(message.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
