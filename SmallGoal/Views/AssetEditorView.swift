import SwiftData
import SwiftUI

struct AssetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let asset: Asset?
    @State private var type: AssetType
    @State private var name: String
    @State private var code: String
    @State private var market: String
    @State private var quantityOrAmount: Double
    @State private var cost: Double
    @State private var latestPrice: Double
    @State private var previousCloseOrNetValue: Double
    @State private var annualYield: Double
    @State private var startDate: Date
    @State private var maturityDate: Date
    @State private var currency: String
    @State private var note: String

    init(asset: Asset? = nil, initialType: AssetType = .stock) {
        self.asset = asset
        let resolvedType = asset?.type ?? initialType
        _type = State(initialValue: resolvedType)
        _name = State(initialValue: asset?.name ?? "")
        _code = State(initialValue: asset?.code ?? "")
        _market = State(initialValue: asset?.market ?? "CN")
        _quantityOrAmount = State(initialValue: asset?.quantityOrAmount ?? 0)
        _cost = State(initialValue: asset?.cost ?? 0)
        _latestPrice = State(initialValue: asset?.latestPrice ?? 0)
        _previousCloseOrNetValue = State(initialValue: asset?.previousCloseOrNetValue ?? 0)
        _annualYield = State(initialValue: asset?.annualYield ?? 0)
        _startDate = State(initialValue: asset?.startDate ?? .now)
        _maturityDate = State(initialValue: asset?.maturityDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
        _currency = State(initialValue: asset?.currency ?? "CNY")
        _note = State(initialValue: asset?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("资产类型") {
                    Picker("类型", selection: $type) {
                        ForEach(AssetType.allCases) { type in
                            Label(type.title, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                }

                Section("基础信息") {
                    TextField(namePlaceholder, text: $name)
                    if type == .stock || type == .fund {
                        TextField("代码", text: $code)
                            .textInputAutocapitalization(.characters)
                        TextField("市场", text: $market)
                            .textInputAutocapitalization(.characters)
                    }
                    if type == .cash {
                        TextField("币种", text: $currency)
                            .textInputAutocapitalization(.characters)
                    }
                }

                Section(amountSectionTitle) {
                    TextField(amountPlaceholder, value: $quantityOrAmount, format: .number)
                        .keyboardType(.decimalPad)

                    if type == .stock || type == .fund {
                        TextField("持仓成本价", value: $cost, format: .number)
                            .keyboardType(.decimalPad)
                        TextField("最新价格/净值", value: $latestPrice, format: .number)
                            .keyboardType(.decimalPad)
                        TextField("昨收/上一净值", value: $previousCloseOrNetValue, format: .number)
                            .keyboardType(.decimalPad)
                    }

                    if type == .wealthProduct {
                        TextField("年化收益率，例如 0.025", value: $annualYield, format: .number)
                            .keyboardType(.decimalPad)
                        DatePicker("起息日", selection: $startDate, displayedComponents: .date)
                        DatePicker("到期日", selection: $maturityDate, displayedComponents: .date)
                    }
                }

                Section("备注") {
                    TextField("可选", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(asset == nil ? "添加资产" : "编辑资产")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && quantityOrAmount >= 0
    }

    private var namePlaceholder: String {
        switch type {
        case .stock: "股票名称"
        case .fund: "基金名称"
        case .wealthProduct: "理财产品名称"
        case .cash: "账户名称"
        }
    }

    private var amountSectionTitle: String {
        switch type {
        case .stock: "持仓"
        case .fund: "份额"
        case .wealthProduct: "本金"
        case .cash: "余额"
        }
    }

    private var amountPlaceholder: String {
        switch type {
        case .stock: "持仓数量"
        case .fund: "基金份额"
        case .wealthProduct: "本金金额"
        case .cash: "现金金额"
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMarket = market.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "CN" : market.trimmingCharacters(in: .whitespacesAndNewlines)

        if let asset {
            asset.type = type
            asset.name = trimmedName
            asset.code = trimmedCode
            asset.market = trimmedMarket
            asset.quantityOrAmount = quantityOrAmount
            asset.cost = type == .wealthProduct || type == .cash ? quantityOrAmount : cost
            asset.latestPrice = latestPrice
            asset.previousCloseOrNetValue = previousCloseOrNetValue
            asset.annualYield = annualYield
            asset.startDate = startDate
            asset.maturityDate = maturityDate
            asset.currency = currency
            asset.note = note
            asset.updatedAt = .now
        } else {
            let newAsset = Asset(
                type: type,
                name: trimmedName,
                code: trimmedCode,
                market: trimmedMarket,
                quantityOrAmount: quantityOrAmount,
                cost: type == .wealthProduct || type == .cash ? quantityOrAmount : cost,
                latestPrice: latestPrice,
                previousCloseOrNetValue: previousCloseOrNetValue,
                annualYield: annualYield,
                startDate: startDate,
                maturityDate: maturityDate,
                currency: currency,
                note: note
            )
            modelContext.insert(newAsset)
        }
    }
}
