import Foundation

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published private(set) var snapshot = PortfolioSnapshot(
        date: .now,
        totalValue: 0,
        dailyProfitLoss: 0,
        cumulativeProfitLoss: 0,
        assetAllocation: []
    )
    @Published private(set) var performances: [AssetPerformance] = []

    func update(with assets: [Asset]) {
        snapshot = PortfolioCalculator.snapshot(for: assets)
        performances = assets
            .map { PortfolioCalculator.performance(for: $0) }
            .sorted { abs($0.dailyProfitLoss) > abs($1.dailyProfitLoss) }
    }
}
