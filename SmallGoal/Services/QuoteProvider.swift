import Foundation

protocol QuoteProvider {
    func fetchQuotes(for codes: [String]) async throws -> [Quote]
}

enum QuoteProviderError: LocalizedError {
    case missingConfiguration
    case emptyCodes
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "行情源尚未配置"
        case .emptyCodes:
            "没有可刷新的资产代码"
        case .invalidResponse:
            "行情返回数据格式异常"
        }
    }
}
