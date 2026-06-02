//
//  OAuthCallbackServer.swift
//  NotchPro
//

import Foundation
import Network
import Security

/// Local HTTPS listener for Schwab OAuth redirect (https://127.0.0.1:8765).
final class OAuthCallbackServer {
    static let redirectURI = "https://127.0.0.1:8765"
    static let port: UInt16 = 8765

    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?

    func waitForAuthorizationCode(timeout: TimeInterval = 300) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                try startListening()
            } catch {
                continuation.resume(throwing: error)
                self.continuation = nil
            }

            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if self.continuation != nil {
                    self.stop()
                    self.continuation?.resume(throwing: OAuthCallbackError.timedOut)
                    self.continuation = nil
                }
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func startListening() throws {
        guard let identity = try loadLocalhostIdentity() else {
            throw OAuthCallbackError.missingCertificate
        }

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            sec_identity_create(identity)!
        )

        let parameters = NWParameters(tls: tlsOptions)
        parameters.allowLocalEndpointReuse = true

        guard let port = NWEndpoint.Port(rawValue: Self.port) else {
            throw OAuthCallbackError.invalidPort
        }

        let listener = try NWListener(using: parameters, on: port)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.continuation?.resume(throwing: error)
                self?.continuation = nil
            }
        }

        listener.start(queue: .global(qos: .userInitiated))
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let firstLine = request.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""

            if let code = Self.parseAuthorizationCode(from: path) {
                self.sendSuccess(connection: connection)
                self.continuation?.resume(returning: code)
                self.continuation = nil
                self.stop()
            } else {
                self.sendFailure(connection: connection)
                connection.cancel()
            }
        }
    }

    private static func parseAuthorizationCode(from path: String) -> String? {
        guard let queryStart = path.firstIndex(of: "?") else { return nil }
        let query = String(path[path.index(after: queryStart)...])
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == "code" {
                return String(parts[1]).removingPercentEncoding
            }
        }
        return nil
    }

    private func sendSuccess(connection: NWConnection) {
        let body = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>NotchPro</title></head>\
        <body style="font-family:-apple-system;background:#111;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">\
        <div style="text-align:center"><h1>Connected</h1><p>You can close this tab and return to NotchPro.</p></div></body></html>
        """
        respond(connection: connection, status: 200, body: body)
    }

    private func sendFailure(connection: NWConnection) {
        let body = "<html><body><h1>Authorization failed</h1><p>Return to NotchPro and try again.</p></body></html>"
        respond(connection: connection, status: 400, body: body)
    }

    private func respond(connection: NWConnection, status: Int, body: String) {
        let response = """
        HTTP/1.1 \(status) OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func loadLocalhostIdentity() throws -> SecIdentity? {
        guard let url = Bundle.main.url(forResource: "localhost", withExtension: "p12", subdirectory: "OAuthLocalhost")
            ?? Bundle.main.url(forResource: "localhost", withExtension: "p12") else {
            return nil
        }

        let p12Data = try Data(contentsOf: url)
        let options: [String: Any] = [kSecImportExportPassphrase as String: "notchpro-local"]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let identity = array.first?[kSecImportItemIdentity as String] as! SecIdentity? else {
            return nil
        }
        return identity
    }
}

enum OAuthCallbackError: LocalizedError {
    case missingCertificate
    case invalidPort
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingCertificate:
            return "OAuth certificate missing from app bundle."
        case .invalidPort:
            return "Could not open local OAuth port."
        case .timedOut:
            return "Schwab login timed out. Try again."
        }
    }
}
