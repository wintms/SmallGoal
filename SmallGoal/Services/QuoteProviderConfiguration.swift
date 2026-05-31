import Foundation

enum QuoteProviderMode: String, CaseIterable, Identifiable, Codable {
    case mock
    case chinaMarket
    case mxData

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mock: "模拟行情"
        case .chinaMarket: "真实行情"
        case .mxData: "妙想直连"
        }
    }

    var description: String {
        switch self {
        case .mock:
            "使用本地生成的演示价格"
        case .chinaMarket:
            "使用通用行情代理接口"
        case .mxData:
            "iOS 直接请求东方财富妙想 API"
        }
    }
}

struct QuoteProviderConfiguration: Equatable {
    var mode: QuoteProviderMode
    var endpointURLString: String
    var hasAPIKey: Bool

    static let defaultValue = QuoteProviderConfiguration(
        mode: .mock,
        endpointURLString: "",
        hasAPIKey: false
    )

    var endpointURL: URL? {
        let trimmed = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    var canRefresh: Bool {
        switch mode {
        case .mock:
            true
        case .chinaMarket:
            endpointURL != nil
        case .mxData:
            hasAPIKey
        }
    }
}

final class QuoteConfigurationStore: ObservableObject {
    static let apiKeyAccount = "chinaMarketAPIKey"

    @Published private(set) var configuration: QuoteProviderConfiguration

    private let defaults: UserDefaults
    private let credentialStore: CredentialStoring

    private enum DefaultsKey {
        static let mode = "quote.provider.mode"
        static let endpointURLString = "quote.provider.endpointURLString"
    }

    init(
        defaults: UserDefaults = .standard,
        credentialStore: CredentialStoring = KeychainCredentialStore()
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore

        let storedMode = defaults.string(forKey: DefaultsKey.mode)
            .flatMap(QuoteProviderMode.init(rawValue:)) ?? .mock
        let endpoint = defaults.string(forKey: DefaultsKey.endpointURLString) ?? ""
        let hasAPIKey = (try? credentialStore.read(account: Self.apiKeyAccount))?.isEmpty == false

        configuration = QuoteProviderConfiguration(
            mode: storedMode,
            endpointURLString: endpoint,
            hasAPIKey: hasAPIKey
        )
    }

    func apiKey() -> String? {
        try? credentialStore.read(account: Self.apiKeyAccount)
    }

    func update(mode: QuoteProviderMode, endpointURLString: String) {
        defaults.set(mode.rawValue, forKey: DefaultsKey.mode)
        defaults.set(endpointURLString, forKey: DefaultsKey.endpointURLString)
        configuration.mode = mode
        configuration.endpointURLString = endpointURLString
    }

    func saveAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try clearAPIKey()
            return
        }

        try credentialStore.save(trimmed, account: Self.apiKeyAccount)
        configuration.hasAPIKey = true
    }

    func clearAPIKey() throws {
        try credentialStore.delete(account: Self.apiKeyAccount)
        configuration.hasAPIKey = false
    }
}
