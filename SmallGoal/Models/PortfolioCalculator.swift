import Foundation

enum PortfolioCalculator {
    static func snapshot(for assets: [Asset], on date: Date = .now) -> PortfolioSnapshot {
        let totalValue = assets.reduce(0.0) { $0 + Self.currentValue(for: $1, on: date) }
        let dailyProfitLoss = assets.reduce(0.0) { $0 + Self.dailyProfitLoss(for: $1, on: date) }
        let cumulativeProfitLoss = assets.reduce(0.0) { $0 + Self.cumulativeProfitLoss(for: $1, on: date) }

        let allocations = AssetType.allCases.map { type in
            let value = assets
                .filter { $0.type == type }
                .reduce(0.0) { $0 + Self.currentValue(for: $1, on: date) }
            return AssetAllocation(
                type: type,
                value: value,
                percent: totalValue > 0 ? value / totalValue : 0
            )
        }

        return PortfolioSnapshot(
            date: date,
            totalValue: totalValue,
            dailyProfitLoss: dailyProfitLoss,
            cumulativeProfitLoss: cumulativeProfitLoss,
            assetAllocation: allocations
        )
    }

    static func performance(for asset: Asset, on date: Date = .now) -> AssetPerformance {
        AssetPerformance(
            id: asset.id,
            asset: asset,
            currentValue: currentValue(for: asset, on: date),
            costValue: costValue(for: asset),
            dailyProfitLoss: dailyProfitLoss(for: asset, on: date),
            cumulativeProfitLoss: cumulativeProfitLoss(for: asset, on: date)
        )
    }

    static func currentValue(for asset: Asset, on date: Date = .now) -> Double {
        switch asset.type {
        case .stock, .fund:
            let price = asset.latestPrice > 0 ? asset.latestPrice : asset.cost
            return asset.quantityOrAmount * price
        case .wealthProduct:
            let principal = asset.quantityOrAmount
            return principal + accruedYield(for: asset, on: date)
        case .cash:
            return asset.quantityOrAmount
        }
    }

    private static func hkdExchangeRate() -> Double {
        if UserDefaults.standard.object(forKey: "quote.provider.hkdExchangeRate") == nil { return 0.92 }
        let rate = UserDefaults.standard.double(forKey: "quote.provider.hkdExchangeRate")
        return rate > 0 ? rate : 0.92
    }

    static func costValue(for asset: Asset) -> Double {
        switch asset.type {
        case .stock, .fund:
            let rate = asset.market == "HK" ? hkdExchangeRate() : 1.0
            return asset.quantityOrAmount * asset.cost * rate
        case .wealthProduct, .cash:
            return asset.quantityOrAmount
        }
    }

    static func cumulativeProfitLoss(for asset: Asset, on date: Date = .now) -> Double {
        currentValue(for: asset, on: date) - costValue(for: asset)
    }

    static func dailyProfitLoss(for asset: Asset, on date: Date = .now) -> Double {
        switch asset.type {
        case .stock, .fund:
            guard asset.previousCloseOrNetValue > 0 else { return 0 }
            return asset.quantityOrAmount * (asset.latestPrice - asset.previousCloseOrNetValue)
        case .wealthProduct:
            return asset.quantityOrAmount * asset.annualYield / 365
        case .cash:
            return 0
        }
    }

    private static func accruedYield(for asset: Asset, on date: Date) -> Double {
        guard asset.annualYield > 0 else { return 0 }
        let effectiveEnd = min(date, asset.maturityDate)
        let days = max(0, Calendar.current.dateComponents([.day], from: asset.startDate, to: effectiveEnd).day ?? 0)
        return asset.quantityOrAmount * asset.annualYield * Double(days) / 365
    }
}
