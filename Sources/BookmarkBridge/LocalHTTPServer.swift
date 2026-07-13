import Foundation
import Network

final class LocalHTTPServer {
    typealias Response = (Int, Data)
    typealias Handler = (
        _ method: String,
        _ path: String,
        _ body: Data,
        _ completion: @escaping (Response) -> Void
    ) -> Void

    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "BookmarkBridge.HTTP")
    private let handler: Handler
    private var listener: NWListener?

    init(port: UInt16 = 17315, handler: @escaping Handler) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.handler = handler
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                fputs("Bookmark Bridge listener failed: \(error)\n", stderr)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if let request = self.parseRequest(buffer) {
                self.handler(request.method, request.path, request.body) { [weak self] response in
                    self?.send(status: response.0, body: response.1, on: connection)
                }
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, accumulated: buffer)
            }
        }
    }

    private func parseRequest(_ data: Data) -> (method: String, path: String, body: Data)? {
        let marker = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: marker),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let contentLength = lines.dropFirst().compactMap { line -> Int? in
            let pieces = line.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2,
                  pieces[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else {
                return nil
            }
            return Int(pieces[1].trimmingCharacters(in: .whitespaces))
        }.first ?? 0

        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return (String(parts[0]), String(parts[1]), body)
    }

    private func send(status: Int, body: Data, on connection: NWConnection) {
        let reason = status == 200 ? "OK" : status == 204 ? "No Content" : "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
