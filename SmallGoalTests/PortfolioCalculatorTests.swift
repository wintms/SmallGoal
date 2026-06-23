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

    func testFundPerformanceUsesInvestmentTransactionsWhenPresent() {
        let asset = Asset(
            type: .fund,
            name: "指数基金",
            code: "510300",
            quantityOrAmount: 100,
            cost: 1,
            latestPrice: 1.2,
            previousCloseOrNetValue: 1.18
        )
        let first = InvestmentTransaction(amount: 1_000, units: 1_000, netValue: 1)
        let second = InvestmentTransaction(amount: 600, units: 500, netValue: 1.2)
        asset.investmentTransactions = [first, second]

        XCTAssertEqual(PortfolioCalculator.currentValue(for: asset), 1_800, accuracy: 0.001)
        XCTAssertEqual(PortfolioCalculator.costValue(for: asset), 1_600, accuracy: 0.001)
        XCTAssertEqual(PortfolioCalculator.cumulativeProfitLoss(for: asset), 200, accuracy: 0.001)
        XCTAssertEqual(PortfolioCalculator.dailyProfitLoss(for: asset), 30, accuracy: 0.001)
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

        XCTAssertEqual(decoded.version, 3)
        XCTAssertEqual(decoded.assets.count, 1)
        XCTAssertEqual(decoded.assets[0].transactions.count, 2)
        XCTAssertEqual(decoded.assets[0].transactions.map(\.amount).sorted(), [-120, 500])
        XCTAssertTrue(decoded.assets[0].transactions.contains { $0.note == "工资" && $0.date == incomeDate })
    }

    func testPortfolioExportIncludesFundInvestmentRecordsAndPlan() throws {
        let calendar = Calendar(identifier: .gregorian)
        let buyDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let nextDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let asset = Asset(
            type: .fund,
            name: "指数基金",
            code: "510300",
            quantityOrAmount: 1_000,
            cost: 1
        )
        let transaction = InvestmentTransaction(amount: 1_000, units: 1_000, netValue: 1, fee: 1, date: buyDate, note: "定投")
        let plan = RecurringInvestmentPlan(amount: 1_000, feeRate: 0.0015, dayOfMonth: 1, nextDate: nextDate)
        asset.investmentTransactions = [transaction]
        asset.recurringInvestmentPlans = [plan]

        let export = PortfolioExport.from([asset])
        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(PortfolioExport.self, from: data)

        XCTAssertEqual(decoded.version, 3)
        XCTAssertEqual(decoded.assets[0].investmentTransactions.count, 1)
        XCTAssertEqual(decoded.assets[0].investmentTransactions[0].note, "定投")
        XCTAssertEqual(decoded.assets[0].investmentTransactions[0].fee, 1)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans.count, 1)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans[0].amount, 1_000)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans[0].feeRate, 0.0015)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans[0].frequency, RecurringInvestmentFrequency.monthly.rawValue)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans[0].weekday, Weekday.monday.rawValue)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans[0].nextDate, nextDate)
    }

    func testPortfolioExportIncludesWeeklyRecurringInvestmentPlan() throws {
        let calendar = Calendar(identifier: .gregorian)
        let nextDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3))!
        let asset = Asset(
            type: .fund,
            name: "指数基金",
            code: "510300",
            quantityOrAmount: 1_000,
            cost: 1
        )
        let plan = RecurringInvestmentPlan(
            amount: 500,
            feeRate: 0.002,
            frequency: .weekly,
            weekday: .friday,
            dayOfMonth: 1,
            nextDate: nextDate
        )
        asset.recurringInvestmentPlans = [plan]

        let export = PortfolioExport.from([asset])
        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(PortfolioExport.self, from: data)

        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans.count, 1)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans[0].amount, 500)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans[0].feeRate, 0.002)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans[0].frequency, RecurringInvestmentFrequency.weekly.rawValue)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans[0].weekday, Weekday.friday.rawValue)
        XCTAssertEqual(decoded.assets[0].recurringInvestmentPlans[0].nextDate, nextDate)
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
        XCTAssertTrue(decoded.assets[0].investmentTransactions.isEmpty)
        XCTAssertTrue(decoded.assets[0].recurringInvestmentPlans.isEmpty)
    }
}
