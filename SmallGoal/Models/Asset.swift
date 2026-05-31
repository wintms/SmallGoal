import Foundation
import SwiftData
import SwiftUI

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

    var displayCurrency: String {
        switch type {
        case .stock:
            market == "HK" ? "HKD" : "CNY"
        case .fund:
            "CNY"
        case .wealthProduct, .cash:
            currency.isEmpty ? "CNY" : currency
        }
    }
}
