import SwiftData
import SwiftUI

struct AssetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var quoteRefreshService: QuoteRefreshService
    @Query(sort: \Asset.createdAt) private var allAssets: [Asset]

    private let asset: Asset?
    @State private var type: AssetType
    @State private var name: String
    @State private var code: String
    @State private var market: String
    @State private var quantityOrAmount: Double?
    @State private var cost: Double?
    @State private var latestPrice: Double?
    @State private var previousCloseOrNetValue: Double?
    @State private var annualYield: Double
    @State private var startDate: Date
    @State private var maturityDate: Date
    @State private var currency: String
    @State private var note: String
    @State private var isLookingUpQuote = false
    @State private var lookupMessage: String?
    @State private var shouldSyncInitialCashOutflow = true

    init(asset: Asset? = nil, initialType: AssetType = .stock) {
        self.asset = asset
        let resolvedType = asset?.type ?? initialType
        _type = State(initialValue: resolvedType)
        _name = State(initialValue: asset?.name ?? "")
        _code = State(initialValue: asset?.code ?? "")
        _market = State(initialValue: asset?.market ?? "CN")
        _quantityOrAmount = State(initialValue: asset?.quantityOrAmount)
        _cost = State(initialValue: asset?.cost)
        _latestPrice = State(initialValue: asset?.latestPrice)
        _previousCloseOrNetValue = State(initialValue: asset?.previousCloseOrNetValue)
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
                    if type == .stock || type == .fund {
                        HStack {
                            TextField("代码", text: $code)
                                .textInputAutocapitalization(.characters)
                            Button {
                                Task { await lookupQuote() }
                            } label: {
                                if isLookingUpQuote {
                                    ProgressView()
                                } else {
                                    Image(systemName: "magnifyingglass")
                                }
                            }
                            .disabled(!canLookupQuote)
                            .accessibilityLabel("查询并填入")
                        }
                        if let lookupMessage {
                            Text(lookupMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if type == .stock || type == .fund {
                        HStack {
                            TextField(namePlaceholder, text: $name)
                            Button {
                                Task { await lookupName() }
                            } label: {
                                if isLookingUpQuote {
                                    ProgressView()
                                } else {
                                    Image(systemName: "magnifyingglass")
                                }
                            }
                            .disabled(!canLookupName)
                            .accessibilityLabel("按名称查询并填入")
                        }
                    } else {
                        TextField(namePlaceholder, text: $name)
                    }
                    if type == .stock {
                        Picker("市场", selection: $market) {
                            ForEach(Market.allCases) { m in
                                Text(m.title).tag(m.rawValue)
                            }
                        }
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

                if asset == nil && (type == .stock || type == .fund) {
                    Section("现金") {
                        Toggle("同步现金支出", isOn: $shouldSyncInitialCashOutflow)
                        if shouldSyncInitialCashOutflow, let initialCashOutflow {
                            LabeledContent("支出金额", value: FinanceFormatters.valueWithSymbol(initialCashOutflow, symbol: cashOutflowSymbol))
                        }
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
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let qty = quantityOrAmount, qty > 0 else { return false }
        if type == .stock || type == .fund {
            guard let c = cost, c > 0 else { return false }
        }
        return true
    }

    private var canLookupQuote: Bool {
        !isLookingUpQuote && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canLookupName: Bool {
        !isLookingUpQuote && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func lookupQuote() async {
        await lookupQuote(query: code, shouldOverwriteName: false)
    }

    private func lookupName() async {
        await lookupQuote(query: name, shouldOverwriteName: true)
    }

    private func lookupQuote(query: String, shouldOverwriteName: Bool) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        isLookingUpQuote = true
        lookupMessage = nil
        defer { isLookingUpQuote = false }

        do {
            let quote = try await quoteRefreshService.fetchQuote(query: trimmedQuery)
            if shouldOverwriteName || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = quote.name
            }
            if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                code = quote.code
            }
            latestPrice = quote.latestPrice
            previousCloseOrNetValue = quote.previousClose
            if type == .stock, let inferredMarket = inferredMarket(for: quote.code) ?? inferredMarket(for: trimmedQuery) {
                market = inferredMarket.rawValue
            }
            lookupMessage = "已填入 \(quote.name)"
        } catch {
            lookupMessage = "查询失败：\(error.localizedDescription)"
        }
    }

    private func inferredMarket(for code: String) -> Market? {
        let digits = code.filter(\.isNumber)
        if digits.count == 5 {
            return .hk
        }
        if digits.count == 6 {
            return .cn
        }
        return nil
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMarket = market.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "CN" : market.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedQuantity = quantityOrAmount ?? 0
        let resolvedCost = cost ?? 0
        let resolvedLatestPrice = latestPrice ?? 0
        let resolvedPreviousClose = previousCloseOrNetValue ?? 0

        if let asset {
            asset.type = type
            asset.name = trimmedName
            asset.code = trimmedCode
            asset.market = trimmedMarket
            asset.quantityOrAmount = resolvedQuantity
            asset.cost = type == .wealthProduct || type == .cash ? resolvedQuantity : resolvedCost
            asset.latestPrice = resolvedLatestPrice
            asset.previousCloseOrNetValue = resolvedPreviousClose
            asset.annualYield = annualYield
            asset.startDate = startDate
            asset.maturityDate = maturityDate
            asset.currency = currency
            asset.note = note
            if type == .stock || type == .fund {
                asset.isArchived = resolvedQuantity <= 0
            } else {
                asset.isArchived = false
            }
            asset.updatedAt = .now
        } else {
            let newAsset = Asset(
                type: type,
                name: trimmedName,
                code: trimmedCode,
                market: trimmedMarket,
                quantityOrAmount: resolvedQuantity,
                cost: type == .wealthProduct || type == .cash ? resolvedQuantity : resolvedCost,
                latestPrice: resolvedLatestPrice,
                previousCloseOrNetValue: resolvedPreviousClose,
                annualYield: annualYield,
                startDate: startDate,
                maturityDate: maturityDate,
                currency: currency,
                note: note
            )
            modelContext.insert(newAsset)
            createInitialInvestmentTransaction(for: newAsset, quantity: resolvedQuantity, cost: resolvedCost)
            if shouldSyncInitialCashOutflow {
                createInitialCashOutflow(for: newAsset, amount: resolvedQuantity * resolvedCost)
            }
        }
    }

    private var initialCashOutflow: Double? {
        guard type == .stock || type == .fund,
              let quantity = quantityOrAmount,
              let cost,
              quantity > 0,
              cost > 0 else { return nil }
        let amount = quantity * cost
        if type == .stock, (Market(rawValue: market) ?? .cn).needsCNYConversion {
            return amount * Market.rate(for: Market(rawValue: market) ?? .cn)
        }
        return amount
    }

    private var cashOutflowSymbol: String {
        "¥"
    }

    private func createInitialInvestmentTransaction(for asset: Asset, quantity: Double, cost: Double) {
        guard asset.type == .stock || asset.type == .fund,
              quantity > 0,
              cost > 0 else { return }
        let transaction = InvestmentTransaction(
            amount: quantity * cost,
            units: quantity,
            netValue: cost,
            date: asset.createdAt,
            note: "初始持仓"
        )
        transaction.asset = asset
        modelContext.insert(transaction)
    }

    private func createInitialCashOutflow(for asset: Asset, amount: Double) {
        guard asset.type == .stock || asset.type == .fund,
              amount > 0 else { return }
        let resolvedAmount = asset.needsCNYConversion ? amount * Market.rate(for: asset.resolvedMarket) : amount
        let cashTransaction = CashTransaction(
            amount: -resolvedAmount,
            note: "\(asset.type == .stock ? "股票" : "基金")初始持仓：\(asset.name)",
            date: asset.createdAt
        )
        cashTransaction.asset = cashAssetForInitialOutflow()
        modelContext.insert(cashTransaction)
    }

    private func cashAssetForInitialOutflow() -> Asset {
        if let cashAsset = allAssets.first(where: { candidate in
            candidate.type == .cash && (candidate.currency.isEmpty || candidate.currency == "CNY")
        }) {
            return cashAsset
        }

        let cashAsset = Asset(
            type: .cash,
            name: "现金账户",
            quantityOrAmount: 0,
            cost: 0,
            currency: "CNY"
        )
        modelContext.insert(cashAsset)
        return cashAsset
    }
}
