//
//  ClickyAccessCodeKeychainStore.swift
//  leanring-buddy
//
//  Keeps the signed-in person's access code in the macOS Keychain rather
//  than UserDefaults, so it isn't sitting in a plain-text preferences file.
//

import Foundation
import Security

enum ClickyAccessCodeKeychainStore {
    private static let keychainServiceName = "Clicky Access Code"
    private static let keychainAccountName = "worker-access-code"

    private static var baseKeychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: keychainAccountName
        ]
    }

    static func readAccessCode() -> String? {
        var readQuery = baseKeychainQuery
        readQuery[kSecReturnData as String] = true
        readQuery[kSecMatchLimit as String] = kSecMatchLimitOne

        var readResult: AnyObject?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &readResult)
        guard readStatus == errSecSuccess,
              let accessCodeData = readResult as? Data,
              let accessCode = String(data: accessCodeData, encoding: .utf8) else {
            return nil
        }
        return accessCode
    }

    /// Replaces any previously stored code.
    static func saveAccessCode(_ accessCode: String) {
        deleteAccessCode()

        var addQuery = baseKeychainQuery
        addQuery[kSecValueData as String] = Data(accessCode.utf8)
        // Readable once the Mac has been unlocked after boot, which covers
        // Clicky starting as a login item.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("⚠️ Clicky: Failed to save access code to Keychain (status \(addStatus))")
        }
    }

    static func deleteAccessCode() {
        SecItemDelete(baseKeychainQuery as CFDictionary)
    }
}
