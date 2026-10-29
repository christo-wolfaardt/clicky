//
//  ClickyWorkerConnection.swift
//  leanring-buddy
//
//  Single place for talking to the Cloudflare Worker: its URL, attaching
//  the signed-in person's access code to requests, and recognising the
//  Worker's own auth errors. Nothing here is specific to one person's
//  setup: the server address is entered on the sign-in screen.
//

import Foundation

enum ClickyWorkerConnection {
    private static let serverAddressDefaultsKey = "clickyServerAddress"

    /// The Clicky server (Cloudflare Worker) entered at sign-in, e.g.
    /// https://clicky-proxy.example.workers.dev. Empty until someone signs in.
    /// Kept after sign-out so signing back in only needs the code.
    static var workerBaseURL: String {
        UserDefaults.standard.string(forKey: serverAddressDefaultsKey) ?? ""
    }

    static func saveServerAddress(_ serverAddress: String) {
        UserDefaults.standard.set(serverAddress, forKey: serverAddressDefaultsKey)
    }

    /// Turns whatever was typed into a usable base URL: trims spaces, adds
    /// https:// when missing, drops a trailing slash. nil if it isn't a URL.
    static func normalizedServerAddress(from enteredServerAddress: String) -> String? {
        var serverAddress = enteredServerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !serverAddress.lowercased().hasPrefix("http://") && !serverAddress.lowercased().hasPrefix("https://") {
            serverAddress = "https://" + serverAddress
        }
        while serverAddress.hasSuffix("/") {
            serverAddress.removeLast()
        }

        guard let serverURL = URL(string: serverAddress),
              let serverHost = serverURL.host,
              serverHost.contains(".") else {
            return nil
        }
        return serverAddress
    }

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

    /// True when the server only allows this person certain models and the
    /// selected one isn't among them.
    static func isModelNotAllowedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == 403 && nsError.localizedDescription.contains("model_not_allowed")
    }
}
