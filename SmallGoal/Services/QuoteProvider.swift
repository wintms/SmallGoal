import Foundation

protocol QuoteProvider {
    func fetchQuotes(for codes: [String]) async throws -> [Quote]
}

enum QuoteProviderError: LocalizedError {
    case missingConfiguration
    case missingAPIKey
    case emptyCodes
    case invalidURL
    case httpStatus(Int)
    case invalidResponse
    case network(String)
    case decoding(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "行情源尚未配置"
        case .missingAPIKey:
            "API Key 尚未配置"
        case .emptyCodes:
            "没有可刷新的资产代码"
        case .invalidURL:
            "行情接口地址无效"
        case .httpStatus(let statusCode):
            "行情接口返回 HTTP \(statusCode)"
        case .invalidResponse:
            "行情返回数据格式异常"
        case .network(let message):
            "网络请求失败：\(message)"
        case .decoding(let message):
            "行情解析失败：\(message)"
        case .invalidPayload(let message):
            message
        }
    }
}
