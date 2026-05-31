import Foundation

enum QuoteRefreshState: Equatable {
    case idle(message: String)
    case refreshing(message: String)
    case success(message: String, date: Date)
    case warning(message: String, detail: String?, date: Date?)
    case failure(message: String, detail: String?)

    var message: String {
        switch self {
        case .idle(let message),
             .refreshing(let message),
             .success(let message, _),
             .warning(let message, _, _),
             .failure(let message, _):
            message
        }
    }

    var detail: String? {
        switch self {
        case .warning(_, let detail, _),
             .failure(_, let detail):
            detail
        case .idle, .refreshing, .success:
            nil
        }
    }

    var isRefreshing: Bool {
        if case .refreshing = self { return true }
        return false
    }
}

@MainActor
final class QuoteRefreshService: ObservableObject {
    typealias ProviderFactory = (QuoteProviderConfiguration, String?) throws -> QuoteProvider

    @Published private(set) var state: QuoteRefreshState
    @Published private(set) var configuration: QuoteProviderConfiguration
    @Published private(set) var lastSuccessfulRefreshAt: Date?

    private let configurationStore: QuoteConfigurationStore
    private let providerFactory: ProviderFactory

    init(
        configurationStore: QuoteConfigurationStore = QuoteConfigurationStore(),
        providerFactory: @escaping ProviderFactory = QuoteRefreshService.defaultProviderFactory
    ) {
        self.configurationStore = configurationStore
        self.providerFactory = providerFactory
        self.configuration = configurationStore.configuration
        self.state = .idle(message: configurationStore.configuration.mode.description)
    }

    var isRefreshing: Bool {
        state.isRefreshing
    }

    var lastMessage: String {
        state.message
    }

    var lastRefreshAt: Date? {
        lastSuccessfulRefreshAt
    }

    func updateConfiguration(mode: QuoteProviderMode, endpointURLString: String) {
        configurationStore.update(mode: mode, endpointURLString: endpointURLString)
        configuration = configurationStore.configuration
        state = .idle(message: configuration.mode.description)
    }

    func saveAPIKey(_ apiKey: String) throws {
        try configurationStore.saveAPIKey(apiKey)
        configuration = configurationStore.configuration
    }

    func clearAPIKey() throws {
        try configurationStore.clearAPIKey()
        configuration = configurationStore.configuration
    }

    func updateHKDExchangeRate(_ rate: Double) {
        configurationStore.update(hkdExchangeRate: rate)
        configuration = configurationStore.configuration
    }

    func refresh(assets: [Asset]) async {
        guard configuration.canRefresh else {
            state = .failure(
                message: configurationMissingMessage,
                detail: configurationMissingDetail
            )
            return
        }

        for market in Market.allCases where market.needsCNYConversion {
            if let rate = await ExchangeRateService.fetchRate(for: market) {
                Market.saveRate(rate, for: market)
                configuration = configurationStore.configuration
            }
        }

        let quoteBackedAssets = assets.filter { $0.isQuoteBacked && !$0.code.isEmpty }
        let codes = Array(Set(quoteBackedAssets.map(\.code))).sorted()

        guard !codes.isEmpty else {
            state = .warning(
                message: "没有可刷新的股票或基金代码",
                detail: "请先为股票或基金填写代码。",
                date: nil
            )
            return
        }

        await fetchAndApplyQuotes(codes: codes, assets: quoteBackedAssets)
    }

    func testConnection(assets: [Asset]) async {
        guard configuration.canRefresh else {
            state = .failure(
                message: configurationMissingMessage,
                detail: configurationMissingDetail
            )
            return
        }

        let codes = Array(Set(assets.filter { $0.isQuoteBacked && !$0.code.isEmpty }.map(\.code))).sorted()
        guard !codes.isEmpty else {
            state = .success(
                message: "配置格式可用，暂无持仓代码可测试",
                date: .now
            )
            return
        }

        await fetchAndApplyQuotes(codes: codes, assets: [])
    }

    private func fetchAndApplyQuotes(codes: [String], assets: [Asset]) async {
        state = .refreshing(message: "正在刷新行情")

        do {
            let provider = try makeProvider()
            let quotes = try await provider.fetchQuotes(for: codes)
            let quoteByCode = Dictionary(uniqueKeysWithValues: quotes.map { ($0.code, $0) })

            let normalizedRequestCodes = codes.map { normalizedCode($0) }
            print("[QuoteRefresh] 请求代码: \(codes)")
            print("[QuoteRefresh] 规范化后: \(normalizedRequestCodes)")
            print("[QuoteRefresh] 返回Quote代码: \(quotes.map(\.code))")
            let missingNormalized = normalizedRequestCodes.filter { quoteByCode[$0] == nil }
            if !missingNormalized.isEmpty {
                print("[QuoteRefresh] ❌ 缺失代码: \(missingNormalized)")
            }

            for asset in assets {
                let normalizedAssetCode = normalizedCode(asset.code)
                guard let quote = quoteByCode[normalizedAssetCode] else { continue }
                asset.name = asset.name.isEmpty ? quote.name : asset.name
                asset.latestPrice = quote.latestPrice
                asset.previousCloseOrNetValue = quote.previousClose
                asset.quoteUpdatedAt = quote.quoteTime
                asset.updatedAt = .now
            }

            let date = Date.now
            let normalizedCodes = codes.map { normalizedCode($0) }
            let missingCodes = zip(codes, normalizedCodes).filter { quoteByCode[$1] == nil }.map(\.0)
            if missingCodes.isEmpty {
                lastSuccessfulRefreshAt = date
                state = .success(message: "已更新 \(quotes.count) 项", date: date)
            } else {
                if !quotes.isEmpty {
                    lastSuccessfulRefreshAt = date
                }
                state = .warning(
                    message: "部分更新 \(quotes.count) 项",
                    detail: "更新失败：\(missingCodes.joined(separator: ", "))",
                    date: quotes.isEmpty ? nil : date
                )
            }
        } catch {
            state = .failure(
                message: "更新失败",
                detail: error.localizedDescription
            )
        }
    }

    private func normalizedCode(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return raw }
        return String(digits.suffix(6))
    }

    private func makeProvider() throws -> QuoteProvider {
        try providerFactory(configuration, configurationStore.apiKey())
    }

    private var configurationMissingMessage: String {
        switch configuration.mode {
        case .mock:
            "行情源尚未配置"
        case .chinaMarket:
            "行情源尚未配置"
        case .mxData:
            "妙想 API Key 尚未配置"
        }
    }

    private var configurationMissingDetail: String {
        switch configuration.mode {
        case .mock:
            "当前模拟行情无需额外配置。"
        case .chinaMarket:
            "请在设置中填写真实行情接口地址。"
        case .mxData:
            "请在设置 > 行情中保存妙想 API Key。"
        }
    }

    nonisolated private static func defaultProviderFactory(configuration: QuoteProviderConfiguration, apiKey: String?) throws -> QuoteProvider {
        switch configuration.mode {
        case .mock:
            return MockQuoteProvider()
        case .chinaMarket:
            guard let endpoint = configuration.endpointURL else {
                throw QuoteProviderError.missingConfiguration
            }
            return ChinaMarketQuoteProvider(
                endpoint: endpoint,
                apiKey: apiKey
            )
        case .mxData:
            return MXDataQuoteProvider(apiKey: apiKey)
        }
    }
}

enum ExchangeRateService {
    static func fetchRate(for market: Market) async -> Double? {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(market.currency)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = json["rates"] as? [String: Any],
              let cny = rates["CNY"] as? Double,
              cny > 0 else { return nil }
        return cny
    }
}
