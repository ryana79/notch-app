//
//  WebullSignatureHelpers.swift
//  NotchProCore
//

import CryptoKit
import Foundation

public enum WebullSignatureHelpers {
    /// Webull treats an empty JSON object as "no body" for signature MD5 (see OpenAPI recipe).
    public static func includesBodyMD5(_ bodyString: String?) -> Bool {
        guard let bodyString else { return false }
        let trimmed = bodyString.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "{}"
    }

    public static func compactJSONBody(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public static func generateSignature(
        path: String,
        query: [String: String],
        bodyString: String?,
        appKey: String,
        appSecret: String,
        host: String,
        timestamp: String,
        nonce: String
    ) -> String {
        var params = query
        params["host"] = host
        params["x-app-key"] = appKey
        params["x-signature-algorithm"] = "HMAC-SHA1"
        params["x-signature-nonce"] = nonce
        params["x-signature-version"] = "1.0"
        params["x-timestamp"] = timestamp

        let paramString = params.keys.sorted().map { "\($0)=\(params[$0] ?? "")" }.joined(separator: "&")
        let signString: String
        if includesBodyMD5(bodyString), let bodyString {
            let md5 = Insecure.MD5.hash(data: Data(bodyString.utf8))
            let bodyMD5 = md5.map { String(format: "%02X", $0) }.joined()
            signString = "\(path)&\(paramString)&\(bodyMD5)"
        } else {
            signString = "\(path)&\(paramString)"
        }

        let encoded = fullyPercentEncode(signString)
        let key = SymmetricKey(data: Data("\(appSecret)&".utf8))
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(encoded.utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    public static func utcTimestamp(from date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func fullyPercentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed.inverted) ?? value
    }
}
