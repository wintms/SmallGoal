import Foundation
import SwiftData
import SwiftUI
import UserNotifications

enum Market: String, CaseIterable, Identifiable, Codable {
    case cn = "CN"
    case hk = "HK"

    var id: String { rawValue }

    var title: String { rawValue }

    var currency: String {
        switch self {
        case .cn: "CNY"
        case .hk: "HKD"
        }
    }

    var symbol: String {
        switch self {
        case .cn: "¥"
        case .hk: "HK$"
        }
    }

    var needsCNYConversion: Bool { self != .cn }

    var rateDefaultsKey: String { "quote.provider.\(rawValue.lowercased())Rate" }

    static func rate(for market: Market) -> Double {
        let rate = UserDefaults.standard.double(forKey: market.rateDefaultsKey)
        if UserDefaults.standard.object(forKey: market.rateDefaultsKey) == nil {
            return market == .hk ? 0.92 : 1.0
        }
        return rate > 0 ? rate : 1.0
    }

    static func saveRate(_ rate: Double, for market: Market) {
        UserDefaults.standard.set(rate, forKey: market.rateDefaultsKey)
    }
}

enum AssetType: String, CaseIterable, Identifiable, Codable {
    case stock
    case fund
    case wealthProduct
    case cash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stock: "股票"
        case .fund: "基金"
        case .wealthProduct: "理财"
        case .cash: "现金"
        }
    }

    var systemImage: String {
        switch self {
        case .stock: "chart.line.uptrend.xyaxis"
        case .fund: "square.grid.2x2"
        case .wealthProduct: "building.columns"
        case .cash: "banknote"
        }
    }

    var accentColor: Color {
        switch self {
        case .stock: .blue
        case .fund: .purple
        case .wealthProduct: .orange
        case .cash: .mint
        }
    }

    var subduedAccentColor: Color {
        switch self {
        case .stock: Color(red: 0.30, green: 0.48, blue: 0.74)
        case .fund: Color(red: 0.54, green: 0.43, blue: 0.68)
        case .wealthProduct: Color(red: 0.72, green: 0.52, blue: 0.30)
        case .cash: Color(red: 0.28, green: 0.58, blue: 0.55)
        }
    }
}

enum RecurringInvestmentFrequency: String, CaseIterable, Identifiable, Codable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "每日"
        case .weekly: "每周"
        case .monthly: "每月"
        }
    }
}

enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .monday: "周一"
        case .tuesday: "周二"
        case .wednesday: "周三"
        case .thursday: "周四"
        case .friday: "周五"
        }
    }
}

@Model
final class Asset {
    @Attribute(.unique) var id: UUID
    var typeRaw: String
    var name: String
    var code: String
    var market: String
    var quantityOrAmount: Double
    var cost: Double
    var latestPrice: Double
    var previousCloseOrNetValue: Double
    var annualYield: Double
    var startDate: Date
    var maturityDate: Date
    var currency: String
    var note: String
    var quoteUpdatedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \CashTransaction.asset) var transactions: [CashTransaction]?
    @Relationship(deleteRule: .cascade, inverse: \InvestmentTransaction.asset) var investmentTransactions: [InvestmentTransaction]?
    @Relationship(deleteRule: .cascade, inverse: \RecurringInvestmentPlan.asset) var recurringInvestmentPlans: [RecurringInvestmentPlan]?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        type: AssetType,
        name: String,
        code: String = "",
        market: String = "CN",
        quantityOrAmount: Double,
        cost: Double,
        latestPrice: Double = 0,
        previousCloseOrNetValue: Double = 0,
        annualYield: Double = 0,
        startDate: Date = .now,
        maturityDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now,
        currency: String = "CNY",
        note: String = "",
        quoteUpdatedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.name = name
        self.code = code
        self.market = market
        self.quantityOrAmount = quantityOrAmount
        self.cost = cost
        self.latestPrice = latestPrice
        self.previousCloseOrNetValue = previousCloseOrNetValue
        self.annualYield = annualYield
        self.startDate = startDate
        self.maturityDate = maturityDate
        self.currency = currency
        self.note = note
        self.quoteUpdatedAt = quoteUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var type: AssetType {
        get { AssetType(rawValue: typeRaw) ?? .cash }
        set { typeRaw = newValue.rawValue }
    }

    var displayCode: String {
        code.isEmpty ? market : "\(market) \(code)"
    }

    var isQuoteBacked: Bool {
        type == .stock || type == .fund
    }

    var resolvedMarket: Market { Market(rawValue: market) ?? .cn }

    var displayCurrency: String {
        switch type {
        case .stock:
            resolvedMarket.currency
        case .fund:
            "CNY"
        case .wealthProduct, .cash:
            currency.isEmpty ? "CNY" : currency
        }
    }

    var currencySymbol: String {
        type == .stock ? resolvedMarket.symbol : "¥"
    }

    var needsCNYConversion: Bool {
        type == .stock && resolvedMarket.needsCNYConversion
    }

    var cashBalance: Double {
        let net = (transactions ?? []).reduce(0) { $0 + $1.amount }
        return quantityOrAmount + net
    }

    var fundUnits: Double {
        let recordedUnits = (investmentTransactions ?? []).reduce(0) { $0 + $1.units }
        return recordedUnits > 0 ? recordedUnits : quantityOrAmount
    }

    var fundCostValue: Double {
        let recordedCost = (investmentTransactions ?? []).reduce(0) { $0 + $1.amount }
        return recordedCost > 0 ? recordedCost : quantityOrAmount * cost
    }

    var primaryRecurringInvestmentPlan: RecurringInvestmentPlan? {
        (recurringInvestmentPlans ?? [])
            .sorted { $0.createdAt < $1.createdAt }
            .first
    }
}

@Model
final class CashTransaction {
    @Attribute(.unique) var id: UUID
    var amount: Double
    var note: String
    var date: Date
    var createdAt: Date
    var asset: Asset?

    init(amount: Double, note: String = "", date: Date = .now) {
        self.id = UUID()
        self.amount = amount
        self.note = note
        self.date = date
        self.createdAt = .now
    }
}

@Model
final class InvestmentTransaction {
    @Attribute(.unique) var id: UUID
    var amount: Double
    var units: Double
    var netValue: Double
    var fee: Double
    var date: Date
    var note: String
    var createdAt: Date
    var asset: Asset?

    init(
        amount: Double,
        units: Double,
        netValue: Double,
        fee: Double = 0,
        date: Date = .now,
        note: String = ""
    ) {
        self.id = UUID()
        self.amount = amount
        self.units = units
        self.netValue = netValue
        self.fee = fee
        self.date = date
        self.note = note
        self.createdAt = .now
    }
}

@Model
final class RecurringInvestmentPlan {
    @Attribute(.unique) var id: UUID
    var amount: Double
    var feeRate: Double = 0
    var frequencyRaw: String = RecurringInvestmentFrequency.monthly.rawValue
    var weekday: Int = Weekday.monday.rawValue
    var dayOfMonth: Int
    var nextDate: Date
    var isEnabled: Bool
    var note: String
    var createdAt: Date
    var updatedAt: Date
    var asset: Asset?

    init(
        amount: Double,
        feeRate: Double = 0,
        frequency: RecurringInvestmentFrequency = .monthly,
        weekday: Weekday = .monday,
        dayOfMonth: Int = 1,
        nextDate: Date,
        isEnabled: Bool = true,
        note: String = ""
    ) {
        self.id = UUID()
        self.amount = amount
        self.feeRate = max(0, feeRate)
        self.frequencyRaw = frequency.rawValue
        self.weekday = weekday.rawValue
        self.dayOfMonth = max(1, min(31, dayOfMonth))
        self.nextDate = nextDate
        self.isEnabled = isEnabled
        self.note = note
        self.createdAt = .now
        self.updatedAt = .now
    }

    var frequency: RecurringInvestmentFrequency {
        get { RecurringInvestmentFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var selectedWeekday: Weekday {
        get { Weekday(rawValue: weekday) ?? .monday }
        set { weekday = newValue.rawValue }
    }
}

enum RecurringInvestmentNotificationService {
    static func identifier(for plan: RecurringInvestmentPlan) -> String {
        "recurringInvestmentPlan.\(plan.id.uuidString)"
    }

    static func scheduleNotification(for plan: RecurringInvestmentPlan, assetName: String, symbol: String) async {
        guard plan.isEnabled else {
            cancelNotification(for: plan)
            return
        }

        let fireDate = notificationDate(for: plan.nextDate)
        guard fireDate > .now else {
            cancelNotification(for: plan)
            return
        }

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "定投提醒"
            content.body = "今天有一笔\(assetName)定投待确认：\(FinanceFormatters.valueWithSymbol(plan.amount, symbol: symbol))"
            content.sound = .default

            var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
            components.hour = 21
            components.minute = 45

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier(for: plan), content: content, trigger: trigger)
            center.removePendingNotificationRequests(withIdentifiers: [identifier(for: plan)])
            try await center.add(request)
        } catch {
            return
        }
    }

    static func cancelNotification(for plan: RecurringInvestmentPlan) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: plan)])
    }

    static func scheduleNotifications(for assets: [Asset]) async {
        for asset in assets where asset.type == .fund {
            for plan in asset.recurringInvestmentPlans ?? [] {
                await scheduleNotification(for: plan, assetName: asset.name, symbol: asset.currencySymbol)
            }
        }
    }

    private static func notificationDate(for date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = 21
        components.minute = 45
        return Calendar.current.date(from: components) ?? date
    }
}
