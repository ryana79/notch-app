//
//  BrokerageConnectionTests.swift
//  NotchProTests
//

import NotchProCore
import XCTest

final class BrokerTokenRecordTests: XCTestCase {
    func testAccessValidWithExpiryBuffer() {
        let record = BrokerTokenRecord(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(200),
            refreshExpiresAt: Date().addingTimeInterval(3600),
            providerUserID: "default",
            scopes: nil
        )
        XCTAssertTrue(record.isAccessValid(buffer: 180))
        XCTAssertFalse(record.isAccessValid(buffer: 300))
    }

    func testRefreshValidRequiresToken() {
        let withoutRefresh = BrokerTokenRecord(
            accessToken: "access",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(-60),
            refreshExpiresAt: nil,
            providerUserID: "default",
            scopes: nil
        )
        XCTAssertFalse(withoutRefresh.isRefreshValid())
    }
}

final class BrokerageConnectionErrorTests: XCTestCase {
    func testInvalidGrantRequiresReauthorization() {
        XCTAssertTrue(BrokerageConnectionError.invalidGrant.requiresReauthorization)
        XCTAssertFalse(BrokerageConnectionError.rateLimited.requiresReauthorization)
    }

    func testRetryableHTTPStatuses() {
        XCTAssertTrue(BrokerageConnectionError.apiHTTP(status: 503, debugCode: "test").isRetryable)
        XCTAssertFalse(BrokerageConnectionError.invalidGrant.isRetryable)
    }
}

final class SchwabOAuthParsingTests: XCTestCase {
    func testParseAuthorizationCodeFromRedirectURL() {
        let url = URL(string: "https://127.0.0.1:8765/?code=abc123&state=xyz")!
        XCTAssertEqual(SchwabOAuthHelpers.parseAuthorizationCode(from: url), "abc123")
    }

    func testPKCEChallengeIsDeterministic() {
        let verifier = "test-verifier-value"
        let challenge = SchwabOAuthHelpers.codeChallenge(for: verifier)
        XCTAssertFalse(challenge.isEmpty)
        XCTAssertEqual(SchwabOAuthHelpers.codeChallenge(for: verifier), challenge)
    }
}

final class KeychainTokenStoreTests: XCTestCase {
    func testAccountKeyIncludesProviderAndUser() {
        XCTAssertEqual(
            KeychainTokenStore.accountKey(provider: .schwab, userID: "user-1"),
            "schwab.user-1"
        )
    }
}

final class WebullSignatureTests: XCTestCase {
    func testEmptyJSONObjectOmitsBodyMD5FromSignature() {
        let args = (
            path: "/openapi/auth/token/create",
            query: [String: String](),
            appKey: "demo_key",
            appSecret: "demo_secret",
            host: "api.webull.com",
            timestamp: "2025-11-13T01:37:20Z",
            nonce: "abc123"
        )

        let withoutBody = WebullSignatureHelpers.generateSignature(
            path: args.path,
            query: args.query,
            bodyString: nil,
            appKey: args.appKey,
            appSecret: args.appSecret,
            host: args.host,
            timestamp: args.timestamp,
            nonce: args.nonce
        )
        let withEmptyObject = WebullSignatureHelpers.generateSignature(
            path: args.path,
            query: args.query,
            bodyString: "{}",
            appKey: args.appKey,
            appSecret: args.appSecret,
            host: args.host,
            timestamp: args.timestamp,
            nonce: args.nonce
        )

        XCTAssertEqual(withoutBody, withEmptyObject)
        XCTAssertFalse(withEmptyObject.isEmpty)
    }

    func testTokenCheckBodyIncludesMD5() {
        let withTokenBody = WebullSignatureHelpers.generateSignature(
            path: "/openapi/auth/token/check",
            query: [:],
            bodyString: #"{"token":"abc123"}"#,
            appKey: "demo_key",
            appSecret: "demo_secret",
            host: "api.webull.com",
            timestamp: "2025-11-13T01:37:20Z",
            nonce: "abc123"
        )
        let withoutBody = WebullSignatureHelpers.generateSignature(
            path: "/openapi/auth/token/check",
            query: [:],
            bodyString: nil,
            appKey: "demo_key",
            appSecret: "demo_secret",
            host: "api.webull.com",
            timestamp: "2025-11-13T01:37:20Z",
            nonce: "abc123"
        )

        XCTAssertNotEqual(withTokenBody, withoutBody)
    }
}
