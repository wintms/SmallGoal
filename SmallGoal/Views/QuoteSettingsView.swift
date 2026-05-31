import SwiftData
import SwiftUI

struct QuoteSettingsView: View {
    @EnvironmentObject private var quoteRefreshService: QuoteRefreshService
    @Query private var assets: [Asset]

    @State private var mode: QuoteProviderMode = .mock
    @State private var endpointURLString = ""
    @State private var apiKeyInput = ""
    @State private var marketRates: [Market: Double] = [:]
    @State private var localMessage: String?

    var body: some View {
        Form {
            Section("行情模式") {
                Picker("模式", selection: $mode) {
                    ForEach(QuoteProviderMode.allCases.filter { $0 == .mxData }) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(mode.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if mode == .mxData {
                Section {
                    SecureField(apiKeyPlaceholder, text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if quoteRefreshService.configuration.hasAPIKey {
                        Button(role: .destructive) {
                            clearAPIKey()
                        } label: {
                            Label("清除 API Key", systemImage: "key.slash")
                        }
                    }
                } header: {
                    Text("东方财富妙想 API")
                } footer: {
                    Text("App 将直接请求妙想 API, API Key 仅保存在本机 Keychain 中。请注意 API 的每日使用次数限制。")
                }
            }

            Section {
                    ForEach(Market.allCases.filter(\.needsCNYConversion)) { market in
                        HStack {
                            Text("\(market.currency) → CNY")
                            Spacer()
                            TextField("1.0", value: Binding(
                                get: { marketRates[market] ?? Market.rate(for: market) },
                                set: { newValue in
                                    marketRates[market] = newValue
                                    Market.saveRate(newValue, for: market)
                                }
                            ), format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }
                } header: {
                    Text("汇率")
                } footer: {
                    Text("外币行情价格将乘以对应汇率转换为人民币，用于首页总览统计。刷新行情时自动更新。")
                }

                Section("状态") {
                LabeledContent("当前状态", value: quoteRefreshService.state.message)
                if let detail = quoteRefreshService.state.detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                if let lastRefreshAt = quoteRefreshService.lastRefreshAt {
                    LabeledContent("上次成功", value: lastRefreshAt.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("可测试代码", value: "\(testableCodes.count)")
                if let localMessage {
                    Text(localMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    saveConfiguration()
                } label: {
                    Label("保存配置", systemImage: "checkmark.circle")
                }

                Button {
                    Task { await testConnection() }
                } label: {
                    if quoteRefreshService.isRefreshing {
                        ProgressView()
                    } else {
                        Label("测试连接", systemImage: "network")
                    }
                }
                .disabled(quoteRefreshService.isRefreshing)
            }
        }
        .navigationTitle("行情设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadConfiguration)
    }

    private var apiKeyPlaceholder: String {
        quoteRefreshService.configuration.hasAPIKey ? "已保存，输入新值可覆盖" : "API Key（可选）"
    }

    private var testableCodes: [String] {
        Array(Set(assets.filter { $0.isQuoteBacked && !$0.code.isEmpty }.map(\.code))).sorted()
    }

    private func loadConfiguration() {
        mode = quoteRefreshService.configuration.mode
        endpointURLString = quoteRefreshService.configuration.endpointURLString
        for market in Market.allCases where market.needsCNYConversion {
            marketRates[market] = Market.rate(for: market)
        }
    }

    private func saveConfiguration() {
        quoteRefreshService.updateConfiguration(mode: mode, endpointURLString: endpointURLString)

        guard !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localMessage = "配置已保存"
            return
        }

        do {
            try quoteRefreshService.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            localMessage = "配置和 API Key 已保存"
        } catch {
            localMessage = error.localizedDescription
        }
    }

    private func clearAPIKey() {
        do {
            try quoteRefreshService.clearAPIKey()
            apiKeyInput = ""
            localMessage = "API Key 已清除"
        } catch {
            localMessage = error.localizedDescription
        }
    }

    private func testConnection() async {
        saveConfiguration()
        await quoteRefreshService.testConnection(assets: assets)
    }
}
