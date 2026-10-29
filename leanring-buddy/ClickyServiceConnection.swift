//
//  ClickyServiceConnection.swift
//  leanring-buddy
//
//  Single place that decides where Clicky's requests go and how they're
//  authorised. There are two ways to sign in:
//
//  - Clicky server: a Cloudflare Worker someone runs (see worker/). The
//    person enters its address and their personal access code, and the
//    Worker holds the API keys.
//  - Own API keys: the person pastes their own keys and the app calls
//    Anthropic, AssemblyAI and ElevenLabs directly. Only Anthropic is
//    required; without AssemblyAI the on-device Apple speech recogniser is
//    used, and without ElevenLabs the built-in macOS voice speaks.
//
//  Nothing here is specific to one person's setup.
//

import Foundation

enum ClickyConnectionMode: String {
    case clickyServer
    case ownAPIKeys
}

enum ClickyServiceConnection {
    private static let connectionModeDefaultsKey = "clickyConnectionMode"
    private static let serverAddressDefaultsKey = "clickyServerAddress"
    private static let elevenLabsVoiceIDDefaultsKey = "clickyOwnElevenLabsVoiceID"

    private static let anthropicMessagesURL = "https://api.anthropic.com/v1/messages"
    private static let anthropicAPIVersion = "2023-06-01"
    private static let assemblyAITemporaryTokenURL = "https://streaming.assemblyai.com/v3/token?expires_in_seconds=480"

    // MARK: - Stored configuration

    static var connectionMode: ClickyConnectionMode {
        let storedConnectionMode = UserDefaults.standard.string(forKey: connectionModeDefaultsKey)
        return storedConnectionMode.flatMap(ClickyConnectionMode.init(rawValue:)) ?? .clickyServer
    }

    static func saveConnectionMode(_ connectionMode: ClickyConnectionMode) {
        UserDefaults.standard.set(connectionMode.rawValue, forKey: connectionModeDefaultsKey)
    }

    /// The Clicky server (Cloudflare Worker) entered at sign-in, e.g.
    /// https://clicky-proxy.example.workers.dev. Empty until someone signs in.
    /// Kept after sign-out so signing back in only needs the code.
    static var workerBaseURL: String {
        UserDefaults.standard.string(forKey: serverAddressDefaultsKey) ?? ""
    }

    static func saveServerAddress(_ serverAddress: String) {
        UserDefaults.standard.set(serverAddress, forKey: serverAddressDefaultsKey)
    }

    /// Voice ID for own-keys mode. Not a secret, so it lives in UserDefaults.
    static var ownElevenLabsVoiceID: String {
        UserDefaults.standard.string(forKey: elevenLabsVoiceIDDefaultsKey) ?? ""
    }

    static func saveOwnElevenLabsVoiceID(_ elevenLabsVoiceID: String) {
        UserDefaults.standard.set(elevenLabsVoiceID, forKey: elevenLabsVoiceIDDefaultsKey)
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

    // MARK: - What's available in the current mode

    /// In own-keys mode AssemblyAI is optional; without a key, transcription
    /// falls back to Apple's on-device recogniser.
    static var isAssemblyAITranscriptionAvailable: Bool {
        switch connectionMode {
        case .clickyServer:
            return true
        case .ownAPIKeys:
            return ClickyKeychainStore.read(.assemblyAIAPIKey) != nil
        }
    }

    /// In own-keys mode ElevenLabs is optional; without a key and voice ID,
    /// replies are spoken with the built-in macOS voice.
    static var isElevenLabsSpeechAvailable: Bool {
        switch connectionMode {
        case .clickyServer:
            return true
        case .ownAPIKeys:
            return ClickyKeychainStore.read(.elevenLabsAPIKey) != nil && !ownElevenLabsVoiceID.isEmpty
        }
    }

    // MARK: - Requests

    static var chatRequestURL: String {
        switch connectionMode {
        case .clickyServer:
            return "\(workerBaseURL)/chat"
        case .ownAPIKeys:
            return anthropicMessagesURL
        }
    }

    /// Adds the credentials a Claude request needs in the current mode.
    /// The Worker adds the Anthropic headers itself in server mode.
    static func authorizeChatRequest(_ request: inout URLRequest) {
        switch connectionMode {
        case .clickyServer:
            addAccessCodeAuthorization(to: &request)
        case .ownAPIKeys:
            request.setValue(ClickyKeychainStore.read(.anthropicAPIKey) ?? "", forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        }
    }

    static func makeTextToSpeechRequest() -> URLRequest {
        switch connectionMode {
        case .clickyServer:
            var request = URLRequest(url: URL(string: "\(workerBaseURL)/tts")!)
            addAccessCodeAuthorization(to: &request)
            return request
        case .ownAPIKeys:
            let textToSpeechURL = "https://api.elevenlabs.io/v1/text-to-speech/\(ownElevenLabsVoiceID)"
            var request = URLRequest(url: URL(string: textToSpeechURL)!)
            request.setValue(ClickyKeychainStore.read(.elevenLabsAPIKey) ?? "", forHTTPHeaderField: "xi-api-key")
            return request
        }
    }

    static func makeTranscriptionTokenRequest() -> URLRequest {
        switch connectionMode {
        case .clickyServer:
            var request = URLRequest(url: URL(string: "\(workerBaseURL)/transcribe-token")!)
            request.httpMethod = "POST"
            addAccessCodeAuthorization(to: &request)
            return request
        case .ownAPIKeys:
            var request = URLRequest(url: URL(string: assemblyAITemporaryTokenURL)!)
            request.httpMethod = "GET"
            request.setValue(ClickyKeychainStore.read(.assemblyAIAPIKey) ?? "", forHTTPHeaderField: "authorization")
            return request
        }
    }

    /// Adds `Authorization: Bearer <access code>` when signed in to a server.
    /// Without it the Worker answers 401, which the app treats as signed out.
    private static func addAccessCodeAuthorization(to request: inout URLRequest) {
        guard let accessCode = ClickyKeychainStore.read(.clickyServerAccessCode) else { return }
        request.setValue("Bearer \(accessCode)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Recognising the Worker's own errors

    /// True when the Worker rejected the access code (revoked or never valid).
    /// Checks the Worker's error body, not just the status, because an
    /// upstream provider rejecting an API key is also a 401 and must not be
    /// mistaken for a revoked access code.
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
