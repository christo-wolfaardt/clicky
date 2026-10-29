//
//  ClickyWorkerConnection.swift
//  leanring-buddy
//
//  Single place for talking to the Cloudflare Worker: its URL, attaching
//  the signed-in person's access code to requests, and recognising the
//  Worker's own auth errors.
//

import Foundation

enum ClickyWorkerConnection {
    /// Your deployed Cloudflare Worker. Not a secret: every route rejects
    /// requests that don't carry a valid personal access code.
    static let workerBaseURL = "https://your-worker-name.your-subdomain.workers.dev"

    /// Adds `Authorization: Bearer <access code>` when someone is signed in.
    /// Without it the Worker answers 401, which the app treats as signed out.
    static func addAccessCodeAuthorization(to request: inout URLRequest) {
        guard let accessCode = ClickyAccessCodeKeychainStore.readAccessCode() else { return }
        request.setValue("Bearer \(accessCode)", forHTTPHeaderField: "Authorization")
    }

    /// True when the Worker rejected the access code (revoked or never valid).
    /// Checks the Worker's error body, not just the status, because an
    /// upstream provider rejecting one of *your* API keys is also a 401 and
    /// must not sign anyone out.
    static func isInvalidAccessCodeError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == 401 && nsError.localizedDescription.contains("invalid_access_code")
    }

    /// True when this person used up their daily Claude request allowance.
    /// Anthropic's own rate limiting is also a 429, hence the body check.
    static func isDailyLimitReachedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == 429 && nsError.localizedDescription.contains("daily_limit_reached")
    }
}
