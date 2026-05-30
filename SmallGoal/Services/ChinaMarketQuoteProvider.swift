import Foundation

struct ChinaMarketQuoteProvider: QuoteProvider {
    private let endpoint: URL?
    private let session: URLSession
    private let apiKey: String?

    init(endpoint: URL? = nil, apiKey: String? = nil, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    func fetchQuotes(for codes: [String]) async throws -> [Quote] {
        guard !codes.isEmpty else { throw QuoteProviderError.emptyCodes }
        guard let endpoint else { throw QuoteProviderError.missingConfiguration }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "codes", value: codes.joined(separator: ","))
        ]

        if let apiKey, !apiKey.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "apikey", value: apiKey))
        }

        guard let url = components?.url else { throw QuoteProviderError.missingConfiguration }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw QuoteProviderError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload = try decoder.decode(QuoteResponse.self, from: data)
        return payload.quotes.map {
            Quote(
                code: $0.code,
                name: $0.name,
                latestPrice: $0.latestPrice,
                previousClose: $0.previousClose,
                changeAmount: $0.changeAmount,
                changePercent: $0.changePercent,
                quoteTime: $0.quoteTime
            )
        }
    }
}

private struct QuoteResponse: Decodable {
    let quotes: [QuoteDTO]
}

private struct QuoteDTO: Decodable {
    let code: String
    let name: String
    let latestPrice: Double
    let previousClose: Double
    let changeAmount: Double
    let changePercent: Double
    let quoteTime: Date
}
