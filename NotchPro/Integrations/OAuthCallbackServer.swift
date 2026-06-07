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
    private static let keychainTag = "com.notchpro.oauth.localhost"

    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?

    /// Binds the HTTPS listener before Schwab redirects back to localhost.
    func prepare() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try startListening {
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func waitForAuthorizationCode(timeout: TimeInterval = 300) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            if listener == nil {
                do {
                    try startListening(onReady: nil)
                } catch {
                    continuation.resume(throwing: error)
                    self.continuation = nil
                    return
                }
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

    private func startListening(onReady: (() -> Void)?) throws {
        let identity: SecIdentity
        if Thread.isMainThread {
            identity = try loadLocalhostIdentity()
        } else {
            identity = try DispatchQueue.main.sync {
                try loadLocalhostIdentity()
            }
        }

        let tlsOptions = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create(identity) else {
            NSLog("OAuthCallbackServer: sec_identity_create failed after certificate import")
            throw OAuthCallbackError.identityUnavailable
        }
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            secIdentity
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
            switch state {
            case .ready:
                onReady?()
            case .failed(let error):
                Task { @MainActor in
                    self?.continuation?.resume(throwing: error)
                    self?.continuation = nil
                }
            default:
                break
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
                Task { @MainActor in
                    self.continuation?.resume(returning: code)
                    self.continuation = nil
                    self.stop()
                }
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

    private func loadLocalhostIdentity() throws -> SecIdentity {
        let sources: [(String, () throws -> SecIdentity?)] = [
            ("embedded-pem", { try self.loadIdentityFromEmbeddedPEM() }),
            ("bundle-pem", { try self.loadIdentityFromPEM() }),
            ("embedded-p12", { try self.importP12(OAuthLocalhostCertificate.p12Data, passphrase: OAuthLocalhostCertificate.passphrase) }),
            ("bundle-p12", { [self] in
                guard let url = Self.bundleResourceURL(name: "localhost", ext: "p12") else { return nil }
                return try self.importP12(Data(contentsOf: url), passphrase: OAuthLocalhostCertificate.passphrase)
            }),
        ]

        for (label, loader) in sources {
            if let identity = try loader() {
                NSLog("OAuthCallbackServer: loaded TLS identity from \(label)")
                return identity
            }
        }

        NSLog("OAuthCallbackServer: no TLS identity source succeeded")
        throw OAuthCallbackError.missingCertificate
    }

    private func loadIdentityFromEmbeddedPEM() throws -> SecIdentity? {
        guard !OAuthLocalhostCertificate.certPEMData.isEmpty,
              !OAuthLocalhostCertificate.keyPEMData.isEmpty else {
            return nil
        }
        return try loadIdentityFromPEMData(
            certPEMData: OAuthLocalhostCertificate.certPEMData,
            keyPEMData: OAuthLocalhostCertificate.keyPEMData
        )
    }

    private func loadIdentityFromPEM() throws -> SecIdentity? {
        guard let certURL = Self.bundleResourceURL(name: "localhost", ext: "crt"),
              let keyURL = Self.bundleResourceURL(name: "localhost", ext: "key") else {
            return nil
        }

        return try loadIdentityFromPEMData(
            certPEMData: Data(contentsOf: certURL),
            keyPEMData: Data(contentsOf: keyURL)
        )
    }

    private func loadIdentityFromPEMData(certPEMData: Data, keyPEMData: Data) throws -> SecIdentity? {
        let certDER = Self.pemDataToDER(certPEMData)
        guard let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            NSLog("OAuthCallbackServer: certificate parse failed")
            return nil
        }

        guard let keyPEM = String(data: keyPEMData, encoding: .utf8) else {
            return nil
        }
        let keyDER = Self.pemBodyToDER(keyPEM)
        let keyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
        ]
        var keyError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyDER as CFData, keyAttrs as CFDictionary, &keyError) else {
            NSLog("OAuthCallbackServer: private key parse failed")
            return nil
        }

        return Self.installIdentity(certificate: certificate, privateKey: privateKey)
    }

    private func importP12(_ data: Data, passphrase: String) throws -> SecIdentity? {
        guard !data.isEmpty else { return nil }

        let options: [String: Any] = [
            kSecImportExportPassphrase as String: passphrase,
        ]
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let identity = array.first?[kSecImportItemIdentity as String] as! SecIdentity? else {
            NSLog("OAuthCallbackServer: PKCS12 import failed (status \(status))")
            return nil
        }
        return identity
    }

    private static func installIdentity(certificate: SecCertificate, privateKey: SecKey) -> SecIdentity? {
        let tag = keychainTag.data(using: .utf8)!

        let deleteKey: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
        ]
        SecItemDelete(deleteKey as CFDictionary)

        let addKey: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecValueRef as String: privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        guard SecItemAdd(addKey as CFDictionary, nil) == errSecSuccess else { return nil }

        let deleteCert: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: keychainTag,
        ]
        SecItemDelete(deleteCert as CFDictionary)

        let addCert: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: keychainTag,
        ]
        guard SecItemAdd(addCert as CFDictionary, nil) == errSecSuccess else { return nil }

        var identity: SecIdentity?
        guard SecIdentityCreateWithCertificate(nil, certificate, &identity) == errSecSuccess else {
            return nil
        }
        return identity
    }

    private static func pemDataToDER(_ pemData: Data) -> Data {
        guard let pem = String(data: pemData, encoding: .utf8) else { return pemData }
        return pemBodyToDER(pem)
    }

    private static func pemBodyToDER(_ pem: String) -> Data {
        let body = pem
            .split(separator: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: body) ?? Data()
    }

    private static func bundleResourceURL(name: String, ext: String) -> URL? {
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: name, withExtension: ext, subdirectory: "OAuthLocalhost"),
            bundle.url(forResource: name, withExtension: ext),
            bundle.resourceURL?.appendingPathComponent("OAuthLocalhost/\(name).\(ext)"),
            bundle.resourceURL?.appendingPathComponent("\(name).\(ext)"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

enum OAuthCallbackError: LocalizedError {
    case missingCertificate
    case identityUnavailable
    case invalidPort
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingCertificate:
            return "Could not load the Schwab OAuth certificate. Quit and reopen NotchPro, or paste the redirect URL manually in Settings → Integrations."
        case .identityUnavailable:
            return "Could not start the local Schwab login server. Paste the redirect URL manually in Settings → Integrations."
        case .invalidPort:
            return "Could not open local OAuth port 8765. Quit other apps using that port and try again."
        case .timedOut:
            return "Schwab login timed out. Try again."
        }
    }
}
