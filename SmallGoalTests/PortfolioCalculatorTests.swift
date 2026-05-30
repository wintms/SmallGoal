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
}
