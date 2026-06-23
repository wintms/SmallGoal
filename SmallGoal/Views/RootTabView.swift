import SwiftData
import SwiftUI

struct RootTabView: View {
    @Query private var assets: [Asset]

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
            await RecurringInvestmentNotificationService.scheduleNotifications(for: assets)
        }
        .onChange(of: assets.count) { _, _ in
            Task {
                await RecurringInvestmentNotificationService.scheduleNotifications(for: assets)
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Asset.self, inMemory: true)
        .environmentObject(QuoteRefreshService())
}
