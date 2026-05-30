import Foundation

@MainActor
final class QuoteRefreshService: ObservableObject {
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastMessage = "使用模拟行情"
    @Published private(set) var lastRefreshAt: Date?

    private let provider: QuoteProvider

    init(provider: QuoteProvider) {
        self.provider = provider
    }

    func refresh(assets: [Asset]) async {
        let quoteBackedAssets = assets.filter { $0.isQuoteBacked && !$0.code.isEmpty }
        let codes = Array(Set(quoteBackedAssets.map(\.code))).sorted()

        guard !codes.isEmpty else {
            lastMessage = "没有可刷新的股票或基金代码"
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let quotes = try await provider.fetchQuotes(for: codes)
            let quoteByCode = Dictionary(uniqueKeysWithValues: quotes.map { ($0.code, $0) })

            for asset in quoteBackedAssets {
                guard let quote = quoteByCode[asset.code] else { continue }
                asset.name = asset.name.isEmpty ? quote.name : asset.name
                asset.latestPrice = quote.latestPrice
                asset.previousCloseOrNetValue = quote.previousClose
                asset.quoteUpdatedAt = quote.quoteTime
                asset.updatedAt = .now
            }

            lastRefreshAt = .now
            lastMessage = "行情已更新 \(quotes.count) 项"
        } catch {
            lastMessage = "行情延迟：\(error.localizedDescription)"
        }
    }
}
