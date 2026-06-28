import SwiftData
import SwiftUI

struct RootTabView: View {
    @Query private var assets: [Asset]

    private var activeAssets: [Asset] {
        assets.filter { !$0.isEffectivelyArchived }
    }

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("首页", systemImage: "chart.pie")
                }

            HoldingsView()
                .tabItem {
                    Label("持仓", systemImage: "list.bullet.rectangle")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .task {
            await RecurringInvestmentNotificationService.scheduleNotifications(for: activeAssets)
        }
        .onChange(of: assets.count) { _, _ in
            Task {
                await RecurringInvestmentNotificationService.scheduleNotifications(for: activeAssets)
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Asset.self, inMemory: true)
        .environmentObject(QuoteRefreshService())
}
