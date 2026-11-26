import Foundation
import Network

enum PlaybackResult {
    case playing, paused, stopped, lowered, normal, noFile, missingFile, unavailable

    var response: (status: String, body: String) {
        switch self {
        case .playing: ("200 OK", "playing")
        case .paused: ("200 OK", "paused")
        case .stopped: ("200 OK", "stopped")
        case .lowered: ("200 OK", "lowered")
        case .normal: ("200 OK", "normal")
        case .noFile: ("409 Conflict", "no jingle selected")
        case .missingFile: ("404 Not Found", "jingle not found")
        case .unavailable: ("503 Service Unavailable", "playback unavailable")
        }
    }
}

struct StreamDeckResponse {
    let status: String
    let body: Data
    let contentType: String

    init(status: String, text: String, contentType: String = "text/plain; charset=utf-8") {
        self.status = status
        body = Data(text.utf8)
        self.contentType = contentType
    }

    init(json: [String: Any]) {
        do {
            body = try JSONSerialization.data(withJSONObject: json)
            status = "200 OK"
            contentType = "application/json; charset=utf-8"
        } catch {
            self = Self(status: "500 Internal Server Error", text: "unable to encode response")
        }
    }
}

enum StreamDeckCommand {
    case status
    case overlayStatus
    case jingles
    case toggle
    case pauseOrResume
    case play(String)
    case fade

    static let host = "127.0.0.1"
    static let port: NWEndpoint.Port = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "JinglesStreamDeckPort") as? Int,
              let rawPort = UInt16(exactly: value), rawPort > 0 else { return 17639 }
        return NWEndpoint.Port(rawValue: rawPort) ?? 17639
    }()
    private static let playPrefix = "/play/"
    private static let filenameCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    init?(target: String) {
        if target == "/status" {
            self = .status
            return
        }
        if target == "/jingles" {
            self = .jingles
            return
        }
        if target == "/toggle" {
            self = .toggle
            return
        }
        if target == "/pause-toggle" {
            self = .pauseOrResume
            return
        }
        if target == "/fade" {
            self = .fade
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
        case .status, .overlayStatus, .jingles, .pauseOrResume:
            return nil
        case .toggle:
            return root + "/toggle"
        case .fade:
            return root + "/fade"
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

    func start(handle: @escaping (StreamDeckCommand) -> StreamDeckResponse, failed: @escaping (String) -> Void) {
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
                             handle: @escaping (StreamDeckCommand) -> StreamDeckResponse) {
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
                self.reply(connection, with: .init(status: "400 Bad Request", text: "invalid request"))
            } else {
                self.readRequest(connection, bytes: received, handle: handle)
            }
        }
    }

    private func handleRequest(_ connection: NWConnection, header: Data,
                               handle: (StreamDeckCommand) -> StreamDeckResponse) {
        let lines = String(decoding: header, as: UTF8.self).components(separatedBy: "\r\n")
        let authority = "host: \(StreamDeckCommand.host):\(StreamDeckCommand.port)"
        let headers = lines.dropFirst().map { $0.lowercased() }
        guard let request = lines.first, headers.contains(authority) else {
            reply(connection, with: .init(status: "400 Bad Request", text: "local control only"))
            return
        }
        let parts = request.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "GET", parts[2] == "HTTP/1.1" else {
            reply(connection, with: .init(status: "404 Not Found", text: "unknown command"))
            return
        }
        let target = String(parts[1])
        let fetchSiteHeaders = headers.filter { $0.hasPrefix("sec-fetch-site:") }
        if target == "/obs/jingle" || target == "/obs/jingle/status" {
            guard fetchSiteHeaders.allSatisfy({ $0 == "sec-fetch-site: same-origin" || $0 == "sec-fetch-site: none" }) else {
                reply(connection, with: .init(status: "400 Bad Request", text: "local overlay only"))
                return
            }
            if target == "/obs/jingle" {
                reply(connection, with: overlayPage)
            } else {
                reply(connection, with: handle(.overlayStatus))
            }
            return
        }
        guard fetchSiteHeaders.isEmpty else {
            reply(connection, with: .init(status: "400 Bad Request", text: "local control only"))
            return
        }
        guard let command = StreamDeckCommand(target: target) else {
            reply(connection, with: .init(status: "404 Not Found", text: "unknown command"))
            return
        }
        reply(connection, with: handle(command))
    }

    private var overlayPage: StreamDeckResponse {
        guard let url = Bundle.main.url(forResource: "JingleOverlay", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            return .init(status: "404 Not Found", text: "overlay unavailable")
        }
        return .init(status: "200 OK", text: html, contentType: "text/html; charset=utf-8")
    }

    private func reply(_ connection: NWConnection, with response: StreamDeckResponse) {
        let header = "HTTP/1.1 \(response.status)\r\nContent-Type: \(response.contentType)\r\n"
            + "Content-Length: \(response.body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + response.body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
