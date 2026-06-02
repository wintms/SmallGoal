import Foundation
import SwiftData
import SwiftUI

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
