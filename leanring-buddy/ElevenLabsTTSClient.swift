//
//  ElevenLabsTTSClient.swift
//  leanring-buddy
//
//  Speaks Claude's replies. Uses ElevenLabs (through the Clicky server, or
//  directly with the person's own key) and falls back to the built-in
//  macOS voice when someone using their own keys hasn't added ElevenLabs.
//

import AppKit
import AVFoundation
import Foundation

@MainActor
final class ElevenLabsTTSClient {
    private let session: URLSession

    /// The audio player for the current TTS playback. Kept alive so the
    /// audio finishes playing even if the caller doesn't hold a reference.
    private var audioPlayer: AVAudioPlayer?

    /// Used instead of ElevenLabs when it isn't configured in own-keys mode.
    private let systemVoiceSynthesizer = NSSpeechSynthesizer()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    /// Speaks `text` and returns once playback has started.
    /// Throws on network or decoding errors. Cancellation-safe.
    func speakText(_ text: String) async throws {
        guard ClickyServiceConnection.isElevenLabsSpeechAvailable else {
            systemVoiceSynthesizer.startSpeaking(text)
            print("🔊 System voice: speaking \(text.count) characters")
            return
        }

        var request = ClickyServiceConnection.makeTextToSpeechRequest()
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ElevenLabsTTS", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ElevenLabsTTS", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "TTS API error (\(httpResponse.statusCode)): \(errorBody)"])
        }

        try Task.checkCancellation()

        let player = try AVAudioPlayer(data: data)
        self.audioPlayer = player
        player.play()
        print("🔊 ElevenLabs TTS: playing \(data.count / 1024)KB audio")
    }

    /// Whether reply audio is currently playing back.
    var isPlaying: Bool {
        (audioPlayer?.isPlaying ?? false) || systemVoiceSynthesizer.isSpeaking
    }

    /// Stops any in-progress playback immediately.
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        systemVoiceSynthesizer.stopSpeaking()
    }
}
