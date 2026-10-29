//
//  ClickyKeychainStore.swift
//  leanring-buddy
//
//  Keeps credentials (the Clicky server access code, or the person's own
//  API keys) in the macOS Keychain rather than UserDefaults, so they
//  aren't sitting in a plain-text preferences file.
//

import Foundation
import Security

enum ClickyKeychainStore {
    /// Each credential is a separate Keychain item under the same service.
    enum CredentialAccount: String, CaseIterable {
        case clickyServerAccessCode = "worker-access-code"
        case anthropicAPIKey = "anthropic-api-key"
        case assemblyAIAPIKey = "assemblyai-api-key"
        case elevenLabsAPIKey = "elevenlabs-api-key"
    }

    private static let keychainServiceName = "Clicky"

    private static func baseKeychainQuery(for credentialAccount: CredentialAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: credentialAccount.rawValue
        ]
    }

    static func read(_ credentialAccount: CredentialAccount) -> String? {
        var readQuery = baseKeychainQuery(for: credentialAccount)
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var readResult: AnyObject?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &readResult)
        guard readStatus == errSecSuccess,
              let credentialData = readResult as? Data,
              let credential = String(data: credentialData, encoding: .utf8),
              !credential.isEmpty else {
            return nil
        }
        return credential
    }

    /// Replaces any previously stored value. An empty value just deletes it.
    static func save(_ credential: String, as credentialAccount: CredentialAccount) {
        delete(credentialAccount)
        guard !credential.isEmpty else { return }

        var addQuery = baseKeychainQuery(for: credentialAccount)
        addQuery[kSecValueData as String] = Data(credential.utf8)
        // Readable once the Mac has been unlocked after boot, which covers
        // Clicky starting as a login item.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("⚠️ Clicky: Failed to save \(credentialAccount.rawValue) to Keychain (status \(addStatus))")
        }
    }

    static func delete(_ credentialAccount: CredentialAccount) {
        SecItemDelete(baseKeychainQuery(for: credentialAccount) as CFDictionary)
    }

    static func deleteAllCredentials() {
        for credentialAccount in CredentialAccount.allCases {
            delete(credentialAccount)
        }
    }
}
