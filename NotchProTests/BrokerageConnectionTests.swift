//
//  BrokerageConnectionTests.swift
//  NotchProTests
//

import XCTest
@testable import NotchPro

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
        XCTAssertEqual(SchwabAuthService.parseAuthorizationCode(from: url), "abc123")
    }

    func testPKCEChallengeIsDeterministic() {
        let verifier = "test-verifier-value"
        let challenge = SchwabAuthService.codeChallenge(for: verifier)
        XCTAssertFalse(challenge.isEmpty)
        XCTAssertEqual(SchwabAuthService.codeChallenge(for: verifier), challenge)
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
