import XCTest
@testable import SmallGoal

final class PortfolioCalculatorTests: XCTestCase {
    func testStockProfitLossUsesLatestAndPreviousClose() {
        let asset = Asset(
            type: .stock,
            name: "测试股票",
            code: "000001",
            quantityOrAmount: 100,
            cost: 9,
            latestPrice: 10,
            previousCloseOrNetValue: 9.5
        )

        XCTAssertEqual(PortfolioCalculator.currentValue(for: asset), 1_000, accuracy: 0.001)
        XCTAssertEqual(PortfolioCalculator.cumulativeProfitLoss(for: asset), 100, accuracy: 0.001)
        XCTAssertEqual(PortfolioCalculator.dailyProfitLoss(for: asset), 50, accuracy: 0.001)
    }

    func testCashDoesNotCreateProfitLoss() {
        let asset = Asset(
            type: .cash,
            name: "现金",
            quantityOrAmount: 5_000,
            cost: 5_000
        )

        XCTAssertEqual(PortfolioCalculator.currentValue(for: asset), 5_000, accuracy: 0.001)
        XCTAssertEqual(PortfolioCalculator.dailyProfitLoss(for: asset), 0, accuracy: 0.001)
        XCTAssertEqual(PortfolioCalculator.cumulativeProfitLoss(for: asset), 0, accuracy: 0.001)
    }

    func testWealthProductAccruesDailyYield() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let current = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let maturity = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let asset = Asset(
            type: .wealthProduct,
            name: "理财",
            quantityOrAmount: 10_000,
            cost: 10_000,
            annualYield: 0.0365,
            startDate: start,
            maturityDate: maturity
        )

        XCTAssertEqual(PortfolioCalculator.currentValue(for: asset, on: current), 10_030, accuracy: 0.001)
        XCTAssertEqual(PortfolioCalculator.dailyProfitLoss(for: asset, on: current), 1, accuracy: 0.001)
    }

    func testPortfolioExportIncludesCashTransactions() throws {
        let calendar = Calendar(identifier: .gregorian)
        let incomeDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let expenseDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 2))!
        let asset = Asset(
            type: .cash,
            name: "现金账户",
            quantityOrAmount: 1_000,
            cost: 1_000
        )
        let income = CashTransaction(amount: 500, note: "工资", date: incomeDate)
        let expense = CashTransaction(amount: -120, note: "买入基金", date: expenseDate)
        asset.transactions = [income, expense]

        let export = PortfolioExport.from([asset])
        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(PortfolioExport.self, from: data)

        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.assets.count, 1)
        XCTAssertEqual(decoded.assets[0].transactions.count, 2)
        XCTAssertEqual(decoded.assets[0].transactions.map(\.amount).sorted(), [-120, 500])
        XCTAssertTrue(decoded.assets[0].transactions.contains { $0.note == "工资" && $0.date == incomeDate })
    }

    func testPortfolioExportDecodesLegacyAssetsWithoutTransactions() throws {
        let json = """
        {
          "version": 1,
          "exportedAt": "2026-06-06T00:00:00Z",
          "assets": [
            {
              "type": "cash",
              "name": "现金账户",
              "code": "",
              "market": "CN",
              "quantityOrAmount": 1000,
              "cost": 1000,
              "latestPrice": 0,
              "previousCloseOrNetValue": 0,
              "annualYield": 0,
              "startDate": "2026-06-01T00:00:00Z",
              "maturityDate": "2027-06-01T00:00:00Z",
              "currency": "CNY",
              "note": ""
            }
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(PortfolioExport.self, from: json)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.assets.count, 1)
        XCTAssertTrue(decoded.assets[0].transactions.isEmpty)
    }
}
