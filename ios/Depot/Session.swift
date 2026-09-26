import Foundation
import Security

enum Keychain {
    private static let service = "io.github.ddr-ai.depot"
    private static let account = "token"

    static func get() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String) {
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class Session: ObservableObject {
    @Published var token = ""
    @Published var profile: Profile?
    @Published var revision = 0
    @Published var authError: String?
    let api = GitHubAPI()

    init() {
        if let saved = Keychain.get()?.trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
            token = saved
            api.token = saved
        }
    }

    func apply(token raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        token = trimmed
        api.token = trimmed
        if trimmed.isEmpty {
            Keychain.clear()
            profile = nil
            authError = nil
        } else {
            Keychain.set(trimmed)
            await loadProfile()
        }
        revision += 1
    }

    func loadProfile() async {
        guard !token.isEmpty else {
            profile = nil
            return
        }
        do {
            profile = try await api.profile()
            authError = nil
        } catch is CancellationError {
            return
        } catch {
            profile = nil
            authError = error.localizedDescription
        }
    }
}
