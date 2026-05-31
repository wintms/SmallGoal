import Foundation

struct Quote: Identifiable, Codable, Equatable {
    var id: String { code }
    let code: String
    let name: String
    let latestPrice: Double
    let previousClose: Double
    let changeAmount: Double
    let changePercent: Double
    let quoteTime: Date
}

struct PortfolioSnapshot: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let totalValue: Double
    let dailyProfitLoss: Double
    let cumulativeProfitLoss: Double
    let assetAllocation: [AssetAllocation]
}

struct AssetAllocation: Identifiable, Equatable {
    var id: AssetType { type }
    let type: AssetType
    let value: Double
    let percent: Double
}

struct AssetPerformance: Identifiable {
    let id: UUID
    let asset: Asset
    let currentValue: Double
    let costValue: Double
    let dailyProfitLoss: Double
    let cumulativeProfitLoss: Double

    var dailyProfitLossPercent: Double {
        switch asset.type {
        case .stock, .fund:
            let base = asset.quantityOrAmount * asset.previousCloseOrNetValue
            guard base > 0 else { return 0 }
            return dailyProfitLoss / base
        case .wealthProduct, .cash:
            guard costValue > 0 else { return 0 }
            return dailyProfitLoss / costValue
        }
    }
}
