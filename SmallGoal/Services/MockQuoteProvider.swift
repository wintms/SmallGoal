import Foundation

struct MockQuoteProvider: QuoteProvider {
    func fetchQuotes(for codes: [String]) async throws -> [Quote] {
        guard !codes.isEmpty else { throw QuoteProviderError.emptyCodes }

        try await Task.sleep(nanoseconds: 400_000_000)

        return codes.map { code in
            let seed = Double(abs(code.hashValue % 10_000)) / 100
            let previousClose = max(0.8, seed)
            let direction = code.hashValue.isMultiple(of: 2) ? 1.0 : -1.0
            let changeAmount = previousClose * 0.012 * direction
            let latest = max(0.01, previousClose + changeAmount)

            return Quote(
                code: code,
                name: sampleName(for: code),
                latestPrice: latest,
                previousClose: previousClose,
                changeAmount: changeAmount,
                changePercent: previousClose > 0 ? changeAmount / previousClose : 0,
                quoteTime: .now
            )
        }
    }

    private func sampleName(for code: String) -> String {
        switch code {
        case "600519": "贵州茅台"
        case "510300": "沪深300ETF"
        case "000001": "平安银行"
        default: code
        }
    }
}
