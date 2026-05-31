import Foundation
import XCTest
@testable import SmallGoal

@MainActor
final class QuoteConfigurationTests: XCTestCase {
    func testDefaultConfigurationUsesMockProvider() async {
        let service = QuoteRefreshService(
            configurationStore: makeStore(),
            providerFactory: { _, _ in StaticQuoteProvider(quotes: [
                Quote(
                    code: "600519",
                    name: "贵州茅台",
                    latestPrice: 10,
                    previousClose: 9,
                    changeAmount: 1,
                    changePercent: 0.1111,
                    quoteTime: .now
                )
            ]) }
        )
        let asset = Asset(
            type: .stock,
            name: "测试",
            code: "600519",
            quantityOrAmount: 100,
            cost: 8,
            latestPrice: 8,
            previousCloseOrNetValue: 8
        )

        XCTAssertEqual(service.configuration.mode, .mock)
        await service.refresh(assets: [asset])

        XCTAssertEqual(asset.latestPrice, 10, accuracy: 0.001)
        XCTAssertEqual(asset.previousCloseOrNetValue, 9, accuracy: 0.001)
        XCTAssertTrue(service.lastMessage.contains("行情已更新"))
    }

    func testChinaMarketModeWithoutEndpointFailsBeforeRequest() async {
        let store = makeStore()
        store.update(mode: .chinaMarket, endpointURLString: "")
        let service = QuoteRefreshService(
            configurationStore: store,
            providerFactory: { _, _ in XCTFail("Provider should not be created"); return StaticQuoteProvider(quotes: []) }
        )
        let asset = Asset(
            type: .stock,
            name: "测试",
            code: "600519",
            quantityOrAmount: 100,
            cost: 8,
            latestPrice: 8,
            previousCloseOrNetValue: 7.5
        )

        await service.refresh(assets: [asset])

        XCTAssertEqual(asset.latestPrice, 8, accuracy: 0.001)
        XCTAssertEqual(asset.previousCloseOrNetValue, 7.5, accuracy: 0.001)
        if case .failure(let message, _) = service.state {
            XCTAssertEqual(message, "行情源尚未配置")
        } else {
            XCTFail("Expected failure state")
        }
    }

    func testMXDataModeWithoutAPIKeyFailsBeforeRequest() async {
        let store = makeStore()
        store.update(mode: .mxData, endpointURLString: "")
        let service = QuoteRefreshService(
            configurationStore: store,
            providerFactory: { _, _ in XCTFail("Provider should not be created"); return StaticQuoteProvider(quotes: []) }
        )
        let asset = Asset(
            type: .stock,
            name: "测试",
            code: "600519",
            quantityOrAmount: 100,
            cost: 8,
            latestPrice: 8,
            previousCloseOrNetValue: 7.5
        )

        await service.refresh(assets: [asset])

        XCTAssertEqual(asset.latestPrice, 8, accuracy: 0.001)
        if case .failure(let message, let detail) = service.state {
            XCTAssertEqual(message, "妙想 API Key 尚未配置")
            XCTAssertTrue(detail?.contains("API Key") == true)
        } else {
            XCTFail("Expected failure state")
        }
    }

    func testMXDataModeCreatesProviderWhenAPIKeyExists() async throws {
        let store = makeStore()
        store.update(mode: .mxData, endpointURLString: "")
        try store.saveAPIKey("secret")
        let service = QuoteRefreshService(
            configurationStore: store,
            providerFactory: { configuration, apiKey in
                XCTAssertEqual(configuration.mode, .mxData)
                XCTAssertEqual(apiKey, "secret")
                return StaticQuoteProvider(quotes: [
                    Quote(
                        code: "600519",
                        name: "贵州茅台",
                        latestPrice: 10,
                        previousClose: 9,
                        changeAmount: 1,
                        changePercent: 0.1111,
                        quoteTime: .now
                    )
                ])
            }
        )
        let asset = Asset(
            type: .stock,
            name: "",
            code: "600519",
            quantityOrAmount: 100,
            cost: 8,
            latestPrice: 8,
            previousCloseOrNetValue: 8
        )

        await service.refresh(assets: [asset])

        XCTAssertEqual(asset.latestPrice, 10, accuracy: 0.001)
        XCTAssertEqual(asset.name, "贵州茅台")
        if case .success = service.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected success state")
        }
    }

    func testMXDataPayloadParsesQuoteSchema() throws {
        let payload: [String: Any] = [
            "status": 0,
            "message": "",
            "data": [
                "data": [
                    "searchDataResultDTO": [
                        "entityTagDTOList": [
                            [
                                "fullName": "贵州茅台",
                                "secuCode": "SH600519"
                            ]
                        ],
                        "dataTableDTOList": [
                            [
                                "entityName": "贵州茅台",
                                "nameMap": [
                                    "1": "最新价",
                                    "2": "昨收",
                                    "3": "涨跌额",
                                    "4": "涨跌幅"
                                ],
                                "table": [
                                    "headName": ["2026-05-30 09:45:00"],
                                    "1": [1688.0],
                                    "2": [1670.0],
                                    "3": [18.0],
                                    "4": ["1.08%"]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let quote = try MXDataQuoteProvider.parseQuote(from: payload, fallbackCode: "600519")

        XCTAssertEqual(quote.code, "600519")
        XCTAssertEqual(quote.name, "贵州茅台")
        XCTAssertEqual(quote.latestPrice, 1688, accuracy: 0.001)
        XCTAssertEqual(quote.previousClose, 1670, accuracy: 0.001)
        XCTAssertEqual(quote.changeAmount, 18, accuracy: 0.001)
        XCTAssertEqual(quote.changePercent, 0.0108, accuracy: 0.0001)
    }

    func testMXDataPayloadParsesHeadNameAsIndicatorColumns() throws {
        let payload: [String: Any] = [
            "status": 0,
            "data": [
                "data": [
                    "searchDataResultDTO": [
                        "entityTagDTOList": [
                            [
                                "fullName": "贵州茅台",
                                "secuCode": "600519"
                            ]
                        ],
                        "dataTableDTOList": [
                            [
                                "entityName": "贵州茅台",
                                "returnCodeMap": [
                                    "600519": "贵州茅台"
                                ],
                                "table": [
                                    "headName": ["最新价", "昨收", "涨跌额", "涨跌幅"],
                                    "600519": [1688.0, 1670.0, 18.0, "1.08%"]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let quote = try MXDataQuoteProvider.parseQuote(from: payload, fallbackCode: "600519")

        XCTAssertEqual(quote.latestPrice, 1688, accuracy: 0.001)
        XCTAssertEqual(quote.previousClose, 1670, accuracy: 0.001)
        XCTAssertEqual(quote.changePercent, 0.0108, accuracy: 0.0001)
    }

    func testMXDataPayloadUsesClosePriceWhenLatestPriceIsUnavailable() throws {
        let payload: [String: Any] = [
            "status": 0,
            "data": [
                "data": [
                    "searchDataResultDTO": [
                        "entityTagDTOList": [
                            [
                                "fullName": "贵州茅台",
                                "secuCode": "600519"
                            ]
                        ],
                        "dataTableDTOList": [
                            [
                                "table": [
                                    "headName": ["2026-05-30"],
                                    "1": ["1688.00元"],
                                    "2": ["1670.00元"],
                                    "3": ["1.08%"]
                                ],
                                "nameMap": [
                                    "1": "收盘价",
                                    "2": "前收盘价",
                                    "3": "涨跌幅"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let quote = try MXDataQuoteProvider.parseQuote(from: payload, fallbackCode: "600519")

        XCTAssertEqual(quote.latestPrice, 1688, accuracy: 0.001)
        XCTAssertEqual(quote.previousClose, 1670, accuracy: 0.001)
        XCTAssertEqual(quote.changePercent, 0.0108, accuracy: 0.0001)
    }

    func testMXDataMissingLatestPriceShowsAvailableFields() throws {
        let payload: [String: Any] = [
            "status": 0,
            "data": [
                "data": [
                    "searchDataResultDTO": [
                        "dataTableDTOList": [
                            [
                                "table": [
                                    "headName": ["日期"],
                                    "1": ["2026-05-30"]
                                ],
                                "nameMap": [
                                    "1": "交易日期"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        XCTAssertThrowsError(try MXDataQuoteProvider.parseQuote(from: payload, fallbackCode: "600519")) { error in
            XCTAssertTrue(error.localizedDescription.contains("可用字段"))
            XCTAssertTrue(error.localizedDescription.contains("交易日期"))
        }
    }

    func testPartialQuoteResponseUpdatesReturnedAssetsAndWarns() async {
        let service = QuoteRefreshService(
            configurationStore: makeStore(),
            providerFactory: { _, _ in StaticQuoteProvider(quotes: [
                Quote(
                    code: "600519",
                    name: "贵州茅台",
                    latestPrice: 10,
                    previousClose: 9,
                    changeAmount: 1,
                    changePercent: 0.1111,
                    quoteTime: .now
                )
            ]) }
        )
        let returnedAsset = Asset(
            type: .stock,
            name: "测试1",
            code: "600519",
            quantityOrAmount: 100,
            cost: 8,
            latestPrice: 8,
            previousCloseOrNetValue: 8
        )
        let missingAsset = Asset(
            type: .stock,
            name: "测试2",
            code: "000001",
            quantityOrAmount: 100,
            cost: 6,
            latestPrice: 6,
            previousCloseOrNetValue: 5.8
        )

        await service.refresh(assets: [returnedAsset, missingAsset])

        XCTAssertEqual(returnedAsset.latestPrice, 10, accuracy: 0.001)
        XCTAssertEqual(missingAsset.latestPrice, 6, accuracy: 0.001)
        if case .warning(let message, let detail, let date) = service.state {
            XCTAssertTrue(message.contains("部分更新"))
            XCTAssertTrue(detail?.contains("000001") == true)
            XCTAssertNotNil(date)
        } else {
            XCTFail("Expected warning state")
        }
    }

    func testFailureDoesNotOverwriteExistingPrice() async {
        let service = QuoteRefreshService(
            configurationStore: makeStore(),
            providerFactory: { _, _ in ThrowingQuoteProvider(error: QuoteProviderError.httpStatus(500)) }
        )
        let asset = Asset(
            type: .stock,
            name: "测试",
            code: "600519",
            quantityOrAmount: 100,
            cost: 8,
            latestPrice: 8,
            previousCloseOrNetValue: 7.5
        )

        await service.refresh(assets: [asset])

        XCTAssertEqual(asset.latestPrice, 8, accuracy: 0.001)
        XCTAssertEqual(asset.previousCloseOrNetValue, 7.5, accuracy: 0.001)
        if case .failure(let message, let detail) = service.state {
            XCTAssertEqual(message, "行情刷新失败")
            XCTAssertTrue(detail?.contains("HTTP 500") == true)
        } else {
            XCTFail("Expected failure state")
        }
    }

    func testKeychainCredentialStoreSavesReadsAndDeletesAPIKey() throws {
        let store = KeychainCredentialStore(service: "com.smallgoal.tests.\(UUID().uuidString)")
        let account = "apiKey"

        try store.save("secret-token", account: account)
        XCTAssertEqual(try store.read(account: account), "secret-token")

        try store.delete(account: account)
        XCTAssertNil(try store.read(account: account))
    }

    private func makeStore() -> QuoteConfigurationStore {
        let defaults = UserDefaults(suiteName: "com.smallgoal.tests.\(UUID().uuidString)")!
        return QuoteConfigurationStore(defaults: defaults, credentialStore: InMemoryCredentialStore())
    }
}

final class ChinaMarketQuoteProviderTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testHTTPErrorMapsToQuoteProviderError() async throws {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let provider = ChinaMarketQuoteProvider(
            endpoint: URL(string: "https://quotes.example.com")!,
            session: stubbedSession()
        )

        do {
            _ = try await provider.fetchQuotes(for: ["600519"])
            XCTFail("Expected HTTP error")
        } catch let error as QuoteProviderError {
            XCTAssertEqual(error.localizedDescription, "行情接口返回 HTTP 503")
        }
    }

    func testMalformedJSONMapsToDecodingError() async throws {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"quotes":[{"code":"600519"}]}"#.utf8))
        }
        let provider = ChinaMarketQuoteProvider(
            endpoint: URL(string: "https://quotes.example.com")!,
            session: stubbedSession()
        )

        do {
            _ = try await provider.fetchQuotes(for: ["600519"])
            XCTFail("Expected decoding error")
        } catch let error as QuoteProviderError {
            XCTAssertTrue(error.localizedDescription.contains("行情解析失败"))
        }
    }

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private struct StaticQuoteProvider: QuoteProvider {
    let quotes: [Quote]

    func fetchQuotes(for codes: [String]) async throws -> [Quote] {
        quotes
    }
}

private struct ThrowingQuoteProvider: QuoteProvider {
    let error: Error

    func fetchQuotes(for codes: [String]) async throws -> [Quote] {
        throw error
    }
}

private final class InMemoryCredentialStore: CredentialStoring {
    private var values: [String: String] = [:]

    func read(account: String) throws -> String? {
        values[account]
    }

    func save(_ value: String, account: String) throws {
        values[account] = value
    }

    func delete(account: String) throws {
        values.removeValue(forKey: account)
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: QuoteProviderError.invalidResponse)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
