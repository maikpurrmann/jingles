import Foundation
import Network

enum PlaybackResult {
    case playing, paused, noFile, unavailable

    var response: (status: String, body: String) {
        switch self {
        case .playing: ("200 OK", "playing")
        case .paused: ("200 OK", "paused")
        case .noFile: ("409 Conflict", "no WAV selected")
        case .unavailable: ("503 Service Unavailable", "playback unavailable")
        }
    }
}

// The listener runs on the main queue so local clicks and remote commands use the same player.
final class StreamDeckControl {
    private let port: NWEndpoint.Port = 17639
    private let headerEnd = Data([13, 10, 13, 10])
    private let maxHeaderBytes = 8192
    private var listener: NWListener?

    func start(toggle: @escaping () -> PlaybackResult, failed: @escaping (String) -> Void) {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
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
                self.readRequest(connection, bytes: Data(), toggle: toggle)
            }
            listener.stateUpdateHandler = { state in
                if case .failed = state {
                    failed("Stream Deck ist nicht erreichbar. Port \(self.port) prüfen.")
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            failed("Die Stream-Deck-Steuerung konnte nicht gestartet werden.")
        }
    }

    private func readRequest(_ connection: NWConnection, bytes: Data,
                             toggle: @escaping () -> PlaybackResult) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: maxHeaderBytes - bytes.count) {
            [weak self] data, _, complete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            let received = bytes + (data ?? Data())
            if let end = received.range(of: self.headerEnd)?.lowerBound {
                self.handleRequest(connection, header: received.prefix(upTo: end), toggle: toggle)
            } else if complete || received.count >= self.maxHeaderBytes {
                self.reply(connection, status: "400 Bad Request", body: "invalid request")
            } else {
                self.readRequest(connection, bytes: received, toggle: toggle)
            }
        }
    }

    private func handleRequest(_ connection: NWConnection, header: Data, toggle: () -> PlaybackResult) {
        let lines = String(decoding: header, as: UTF8.self).components(separatedBy: "\r\n")
        guard let request = lines.first,
              lines.dropFirst().contains(where: { $0.lowercased() == "host: 127.0.0.1:\(port)" }),
              !lines.dropFirst().contains(where: { $0.lowercased().hasPrefix("sec-fetch-site:") }) else {
            reply(connection, status: "400 Bad Request", body: "local control only")
            return
        }
        guard request == "GET /toggle HTTP/1.1" else {
            reply(connection, status: "404 Not Found", body: "use GET /toggle")
            return
        }
        let result = toggle().response
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
