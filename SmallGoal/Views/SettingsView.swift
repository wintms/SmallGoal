import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PortfolioExport: Codable {
    var version: Int
    var exportedAt: Date
    var assets: [AssetSnapshot]
}

struct AssetSnapshot: Codable {
    var type: String
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
    var transactions: [CashTransactionSnapshot]

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case code
        case market
        case quantityOrAmount
        case cost
        case latestPrice
        case previousCloseOrNetValue
        case annualYield
        case startDate
        case maturityDate
        case currency
        case note
        case transactions
    }

    init(
        type: String,
        name: String,
        code: String,
        market: String,
        quantityOrAmount: Double,
        cost: Double,
        latestPrice: Double,
        previousCloseOrNetValue: Double,
        annualYield: Double,
        startDate: Date,
        maturityDate: Date,
        currency: String,
        note: String,
        transactions: [CashTransactionSnapshot] = []
    ) {
        self.type = type
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
        self.transactions = transactions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        code = try container.decode(String.self, forKey: .code)
        market = try container.decode(String.self, forKey: .market)
        quantityOrAmount = try container.decode(Double.self, forKey: .quantityOrAmount)
        cost = try container.decode(Double.self, forKey: .cost)
        latestPrice = try container.decode(Double.self, forKey: .latestPrice)
        previousCloseOrNetValue = try container.decode(Double.self, forKey: .previousCloseOrNetValue)
        annualYield = try container.decode(Double.self, forKey: .annualYield)
        startDate = try container.decode(Date.self, forKey: .startDate)
        maturityDate = try container.decode(Date.self, forKey: .maturityDate)
        currency = try container.decode(String.self, forKey: .currency)
        note = try container.decode(String.self, forKey: .note)
        transactions = try container.decodeIfPresent([CashTransactionSnapshot].self, forKey: .transactions) ?? []
    }
}

struct CashTransactionSnapshot: Codable {
    var amount: Double
    var note: String
    var date: Date
}

extension PortfolioExport {
    static func from(_ assets: [Asset]) -> PortfolioExport {
        PortfolioExport(
            version: 2,
            exportedAt: .now,
            assets: assets.map { asset in
                AssetSnapshot(
                    type: asset.typeRaw,
                    name: asset.name,
                    code: asset.code,
                    market: asset.market,
                    quantityOrAmount: asset.quantityOrAmount,
                    cost: asset.cost,
                    latestPrice: asset.latestPrice,
                    previousCloseOrNetValue: asset.previousCloseOrNetValue,
                    annualYield: asset.annualYield,
                    startDate: asset.startDate,
                    maturityDate: asset.maturityDate,
                    currency: asset.currency,
                    note: asset.note,
                    transactions: (asset.transactions ?? []).map { transaction in
                        CashTransactionSnapshot(
                            amount: transaction.amount,
                            note: transaction.note,
                            date: transaction.date
                        )
                    }
                )
            }
        )
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var quoteRefreshService: QuoteRefreshService
    @Query private var assets: [Asset]
    @State private var showingImporter = false
    @State private var showingDeleteConfirmation = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("行情") {
                    NavigationLink {
                        QuoteSettingsView()
                    } label: {
                        Label("行情设置", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    LabeledContent("当前模式", value: quoteRefreshService.configuration.mode.title)
                    LabeledContent("状态", value: quoteRefreshService.lastMessage)
                    if let lastRefreshAt = quoteRefreshService.lastRefreshAt {
                        LabeledContent("上次更新", value: lastRefreshAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                Section("隐私") {
                    Label("无需注册登录", systemImage: "person.crop.circle.badge.checkmark")
                    Label("资产、成本和持仓数量仅保存在本机", systemImage: "lock.shield")
                    Label("数据请求只需要资产代码", systemImage: "network")
                }

                Section("数据") {
                    LabeledContent("资产数量", value: "\(assets.count)")
                    if let exportURL = exportJSON() {
                        ShareLink(item: exportURL) {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("清除所有数据", systemImage: "trash")
                    }
                    if let importMessage {
                        Text(importMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    Text("面向 TestFlight 验证的小目标 MVP。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                importAssets(from: result)
            }
            .alert("确认删除", isPresented: $showingDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { clearAllData() }
            } message: {
                Text("将删除全部 \(assets.count) 项资产数据，此操作不可撤销。建议先导出备份。")
            }
        }
    }

    private func clearAllData() {
        for asset in assets {
            modelContext.delete(asset)
        }
        try? modelContext.save()
    }

    private func exportJSON() -> URL? {
        guard !assets.isEmpty else { return nil }

        let export = PortfolioExport.from(assets)
        guard let data = try? JSONEncoder().encode(export) else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let fileName = "小目标-\(formatter.string(from: .now)).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: tempURL)
        return tempURL
    }

    private func importAssets(from result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let export = try JSONDecoder().decode(PortfolioExport.self, from: data)

            var inserted = 0
            for snapshot in export.assets {
                let asset = Asset(
                    type: AssetType(rawValue: snapshot.type) ?? .stock,
                    name: snapshot.name,
                    code: snapshot.code,
                    market: snapshot.market,
                    quantityOrAmount: snapshot.quantityOrAmount,
                    cost: snapshot.cost,
                    latestPrice: snapshot.latestPrice,
                    previousCloseOrNetValue: snapshot.previousCloseOrNetValue,
                    annualYield: snapshot.annualYield,
                    startDate: snapshot.startDate,
                    maturityDate: snapshot.maturityDate,
                    currency: snapshot.currency,
                    note: snapshot.note
                )
                modelContext.insert(asset)
                for transactionSnapshot in snapshot.transactions {
                    let transaction = CashTransaction(
                        amount: transactionSnapshot.amount,
                        note: transactionSnapshot.note,
                        date: transactionSnapshot.date
                    )
                    transaction.asset = asset
                    modelContext.insert(transaction)
                }
                inserted += 1
            }
            try modelContext.save()
            importMessage = "已导入 \(inserted) 项资产"
        } catch {
            importMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}
