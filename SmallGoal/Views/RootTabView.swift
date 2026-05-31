import SwiftUI

struct RootTabView: View {
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
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Asset.self, inMemory: true)
        .environmentObject(QuoteRefreshService())
}
