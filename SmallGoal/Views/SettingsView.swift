import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var quoteRefreshService: QuoteRefreshService
    @Query private var assets: [Asset]

    var body: some View {
        NavigationStack {
            List {
                Section("行情") {
                    LabeledContent("当前模式", value: "模拟行情")
                    LabeledContent("状态", value: quoteRefreshService.lastMessage)
                    if let lastRefreshAt = quoteRefreshService.lastRefreshAt {
                        LabeledContent("上次更新", value: lastRefreshAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section("隐私") {
                    Label("无需注册登录", systemImage: "person.crop.circle.badge.checkmark")
                    Label("资产、成本和持仓数量仅保存在本机", systemImage: "lock.shield")
                    Label("行情请求只需要资产代码", systemImage: "network")
                }

                Section("数据") {
                    LabeledContent("资产数量", value: "\(assets.count)")
                    LabeledContent("存储方式", value: "SwiftData 本地存储")
                    LabeledContent("导出", value: "后续版本")
                }

                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    Text("面向 TestFlight 验证的个人投资账本 MVP。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}
