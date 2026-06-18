import SwiftData
import SwiftUI

struct AssetDetailView: View {
    let asset: Asset
    @Environment(\.modelContext) private var modelContext
    @State private var showingEditor = false
    @State private var showingAddTransaction = false
    @State private var transactionAmount: Double?
    @State private var transactionNote = ""
    @State private var transactionDate: Date = .now
    @State private var showingAddInvestmentTransaction = false
    @State private var investmentAmount: Double?
    @State private var investmentNetValue: Double?
    @State private var investmentFee: Double?
    @State private var investmentDate: Date = .now
    @State private var investmentNote = ""
    @State private var pendingRecurringPlan: RecurringInvestmentPlan?
    @State private var showingRecurringPlanEditor = false
    @State private var planAmount: Double?
    @State private var planFrequency: RecurringInvestmentFrequency = .monthly
    @State private var planWeekday: Weekday = .monday
    @State private var planDayOfMonth = 1
    @State private var planNextDate: Date = .now
    @State private var planIsEnabled = true
    @State private var planNote = ""

    private var performance: AssetPerformance {
        PortfolioCalculator.performance(for: asset)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: asset.type.systemImage)
                            .font(.title2)
                            .foregroundStyle(asset.type.accentColor)
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(asset.name)
                                .font(.title3.weight(.semibold))
                            Text(asset.displayCode)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        MetricTile(title: "当前价值", value: FinanceFormatters.valueWithSymbol(performance.currentValue, symbol: asset.currencySymbol), tint: .primary)
                        MetricTile(
                            title: "累计盈亏",
                            value: FinanceFormatters.signedValueWithSymbol(performance.cumulativeProfitLoss, symbol: asset.currencySymbol),
                            tint: FinanceFormatters.profitColor(performance.cumulativeProfitLoss),
                            subtitle: cumulativeReturnRate()
                        )
                    }
                }
                .padding(.vertical, 6)
            }

            Section("收益") {
                DetailRow("持仓成本", FinanceFormatters.valueWithSymbol(performance.costValue, symbol: asset.currencySymbol))
                DetailRow("今日盈亏", FinanceFormatters.signedValueWithSymbol(performance.dailyProfitLoss, symbol: asset.currencySymbol), tint: FinanceFormatters.profitColor(performance.dailyProfitLoss))
                DetailRow("今日盈亏率", FinanceFormatters.percent(performance.dailyProfitLossPercent), tint: FinanceFormatters.profitColor(performance.dailyProfitLoss))
            }

            Section("资产信息") {
                DetailRow("类型", asset.type.title)
                DetailRow("币种", asset.displayCurrency)
                if asset.type != .cash {
                    DetailRow(quantityTitle, FinanceFormatters.decimal(displayQuantity))
                }
                if asset.type == .stock || asset.type == .fund {
                    DetailRow("成本价", FinanceFormatters.valueWithSymbol(displayCost, symbol: asset.currencySymbol))
                    DetailRow("最新价格", FinanceFormatters.valueWithSymbol(asset.latestPrice, symbol: asset.currencySymbol))
                    DetailRow("昨收/上一净值", FinanceFormatters.valueWithSymbol(asset.previousCloseOrNetValue, symbol: asset.currencySymbol))
                }
                if asset.type == .wealthProduct {
                    DetailRow("年化收益率", FinanceFormatters.percent(asset.annualYield))
                    DetailRow("起息日", asset.startDate.formatted(date: .abbreviated, time: .omitted))
                    DetailRow("到期日", asset.maturityDate.formatted(date: .abbreviated, time: .omitted))
                }
                if asset.type == .cash {
                    DetailRow("初始现金", FinanceFormatters.valueWithSymbol(asset.quantityOrAmount, symbol: asset.currencySymbol))
                    DetailRow("今日收支", FinanceFormatters.signedValueWithSymbol(performance.dailyProfitLoss, symbol: asset.currencySymbol))
                }
                if let quoteUpdatedAt = asset.quoteUpdatedAt {
                    DetailRow("行情时间", quoteUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if asset.type == .fund {
                if let plan = asset.primaryRecurringInvestmentPlan {
                    Section("定投计划") {
                        DetailRow("金额", FinanceFormatters.valueWithSymbol(plan.amount, symbol: asset.currencySymbol))
                        DetailRow("周期", recurringPlanScheduleText(plan))
                        DetailRow("下次", plan.nextDate.formatted(date: .abbreviated, time: .omitted))
                        DetailRow("状态", plan.isEnabled ? "启用" : "暂停")
                        if isRecurringPlanDue(plan) {
                            Button {
                                prepareInvestmentTransaction(from: plan)
                            } label: {
                                Label("确认本期定投", systemImage: "checkmark.circle")
                            }
                        }
                        Button {
                            prepareRecurringPlanEditor(plan)
                        } label: {
                            Label("编辑计划", systemImage: "calendar.badge.clock")
                        }
                    }
                } else {
                    Section("定投计划") {
                        Button {
                            prepareRecurringPlanEditor(nil)
                        } label: {
                            Label("设置定投计划", systemImage: "calendar.badge.plus")
                        }
                    }
                }

                Section {
                    ForEach(sortedInvestmentTransactions) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.note.isEmpty ? "申购" : tx.note)
                                    .font(.subheadline)
                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(FinanceFormatters.valueWithSymbol(tx.amount, symbol: asset.currencySymbol))
                                    .monospacedDigit()
                                Text("\(FinanceFormatters.decimal(tx.units)) 份 @ \(FinanceFormatters.valueWithSymbol(tx.netValue, symbol: asset.currencySymbol))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .onDelete { offsets in
                        let sorted = sortedInvestmentTransactions
                        var remaining = sorted
                        for index in offsets {
                            let tx = sorted[index]
                            modelContext.delete(tx)
                            remaining.removeAll { $0.id == tx.id }
                        }
                        updateFundSnapshotFields(using: remaining)
                        try? modelContext.save()
                    }

                    Button {
                        prepareInvestmentTransaction()
                    } label: {
                        Label("添加申购", systemImage: "plus.circle")
                    }
                } header: {
                    Text("申购记录")
                }
            }

            if asset.type == .cash {
                Section {
                    ForEach(sortedTransactions) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if !tx.note.isEmpty {
                                    Text(tx.note)
                                        .font(.subheadline)
                                }
                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(FinanceFormatters.signedValueWithSymbol(tx.amount, symbol: asset.currencySymbol))
                                .foregroundStyle(FinanceFormatters.profitColor(tx.amount))
                                .monospacedDigit()
                        }
                    }
                    .onDelete { offsets in
                        let sorted = sortedTransactions
                        for index in offsets {
                            let tx = sorted[index]
                            modelContext.delete(tx)
                        }
                        try? modelContext.save()
                    }

                    Button {
                        transactionAmount = nil
                        transactionNote = ""
                        transactionDate = .now
                        showingAddTransaction = true
                    } label: {
                        Label("添加收支", systemImage: "plus.circle")
                    }
                } header: {
                    Text("收支记录")
                }
            }

            if !asset.note.isEmpty {
                Section("备注") {
                    Text(asset.note)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("资产详情")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            AssetEditorView(asset: asset)
        }
        .sheet(isPresented: $showingAddTransaction) {
            NavigationStack {
                Form {
                    Section("金额") {
                        TextField("正数收入，负数支出", value: $transactionAmount, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                        DatePicker("日期", selection: $transactionDate, displayedComponents: .date)
                    }
                    Section("备注") {
                        TextField("可选", text: $transactionNote)
                    }
                }
                .navigationTitle("添加收支")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingAddTransaction = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加") {
                            addTransaction()
                            showingAddTransaction = false
                        }
                        .disabled((transactionAmount ?? 0) == 0)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingAddInvestmentTransaction) {
            NavigationStack {
                Form {
                    Section("申购") {
                        TextField("金额", value: $investmentAmount, format: .number)
                            .keyboardType(.decimalPad)
                        TextField("成交净值", value: $investmentNetValue, format: .number)
                            .keyboardType(.decimalPad)
                        TextField("手续费", value: $investmentFee, format: .number)
                            .keyboardType(.decimalPad)
                        DatePicker("日期", selection: $investmentDate, displayedComponents: .date)
                        if let estimatedUnits {
                            DetailRow("预计份额", FinanceFormatters.decimal(estimatedUnits))
                        }
                    }
                    Section("备注") {
                        TextField("可选", text: $investmentNote)
                    }
                }
                .navigationTitle("添加申购")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            pendingRecurringPlan = nil
                            showingAddInvestmentTransaction = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加") {
                            addInvestmentTransaction()
                            showingAddInvestmentTransaction = false
                        }
                        .disabled(!canAddInvestmentTransaction)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingRecurringPlanEditor) {
            NavigationStack {
                Form {
                    Section("计划") {
                        TextField("每期金额", value: $planAmount, format: .number)
                            .keyboardType(.decimalPad)
                        Picker("周期", selection: $planFrequency) {
                            ForEach(RecurringInvestmentFrequency.allCases) { frequency in
                                Text(frequency.title).tag(frequency)
                            }
                        }
                        if planFrequency == .weekly {
                            Picker("定投日", selection: $planWeekday) {
                                ForEach(Weekday.allCases) { weekday in
                                    Text(weekday.title).tag(weekday)
                                }
                            }
                        }
                        if planFrequency == .monthly {
                            Stepper("每月 \(planDayOfMonth) 日", value: $planDayOfMonth, in: 1...31)
                        }
                        DatePicker("下次定投日", selection: $planNextDate, displayedComponents: .date)
                        Toggle("启用", isOn: $planIsEnabled)
                    }
                    Section("备注") {
                        TextField("可选", text: $planNote)
                    }
                }
                .navigationTitle(asset.primaryRecurringInvestmentPlan == nil ? "设置定投" : "编辑定投")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingRecurringPlanEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            saveRecurringPlan()
                            showingRecurringPlanEditor = false
                        }
                        .disabled((planAmount ?? 0) <= 0)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var sortedTransactions: [CashTransaction] {
        (asset.transactions ?? []).sorted { $0.date > $1.date }
    }

    private var sortedInvestmentTransactions: [InvestmentTransaction] {
        (asset.investmentTransactions ?? []).sorted { $0.date > $1.date }
    }

    private var displayQuantity: Double {
        asset.type == .fund ? asset.fundUnits : asset.quantityOrAmount
    }

    private var displayCost: Double {
        guard asset.type == .fund else { return asset.cost }
        guard asset.fundUnits > 0 else { return asset.cost }
        return asset.fundCostValue / asset.fundUnits
    }

    private var estimatedUnits: Double? {
        guard let amount = investmentAmount,
              let netValue = investmentNetValue,
              amount > 0,
              netValue > 0 else { return nil }
        let fee = investmentFee ?? 0
        guard amount > fee else { return nil }
        return (amount - fee) / netValue
    }

    private var canAddInvestmentTransaction: Bool {
        estimatedUnits != nil
    }

    private func addTransaction() {
        guard let amount = transactionAmount, amount != 0 else { return }
        let tx = CashTransaction(amount: amount, note: transactionNote, date: transactionDate)
        tx.asset = asset
        modelContext.insert(tx)
        try? modelContext.save()
    }

    private func prepareInvestmentTransaction(from plan: RecurringInvestmentPlan? = nil) {
        investmentAmount = plan?.amount
        investmentNetValue = asset.latestPrice > 0 ? asset.latestPrice : nil
        investmentFee = 0
        investmentDate = plan?.nextDate ?? .now
        investmentNote = plan == nil ? "" : "定投"
        pendingRecurringPlan = plan
        showingAddInvestmentTransaction = true
    }

    private func addInvestmentTransaction() {
        guard let amount = investmentAmount,
              let netValue = investmentNetValue,
              let units = estimatedUnits else { return }
        let fee = investmentFee ?? 0
        let seededTransaction = seedInitialFundTransactionIfNeeded()
        let tx = InvestmentTransaction(
            amount: amount,
            units: units,
            netValue: netValue,
            fee: fee,
            date: investmentDate,
            note: investmentNote
        )
        tx.asset = asset
        modelContext.insert(tx)
        if let pendingRecurringPlan {
            pendingRecurringPlan.nextDate = nextRecurringDate(after: pendingRecurringPlan.nextDate, for: pendingRecurringPlan)
            pendingRecurringPlan.updatedAt = .now
        }
        updateFundSnapshotFields(adding: [seededTransaction, tx].compactMap { $0 })
        asset.updatedAt = .now
        pendingRecurringPlan = nil
        try? modelContext.save()
    }

    private func seedInitialFundTransactionIfNeeded() -> InvestmentTransaction? {
        guard asset.type == .fund,
              (asset.investmentTransactions ?? []).isEmpty,
              asset.quantityOrAmount > 0,
              asset.cost > 0 else { return nil }
        let tx = InvestmentTransaction(
            amount: asset.quantityOrAmount * asset.cost,
            units: asset.quantityOrAmount,
            netValue: asset.cost,
            date: asset.createdAt,
            note: "初始持仓"
        )
        tx.asset = asset
        modelContext.insert(tx)
        return tx
    }

    private func updateFundSnapshotFields(adding pendingTransactions: [InvestmentTransaction] = []) {
        guard asset.type == .fund else { return }
        var transactions = asset.investmentTransactions ?? []
        transactions.append(contentsOf: pendingTransactions)
        updateFundSnapshotFields(using: transactions)
    }

    private func updateFundSnapshotFields(using transactions: [InvestmentTransaction]) {
        guard asset.type == .fund else { return }
        let units = transactions.reduce(0) { $0 + $1.units }
        let costValue = transactions.reduce(0) { $0 + $1.amount }
        guard units > 0 else {
            asset.quantityOrAmount = 0
            asset.cost = 0
            asset.updatedAt = .now
            return
        }
        asset.quantityOrAmount = units
        asset.cost = costValue / units
        asset.updatedAt = .now
    }

    private func prepareRecurringPlanEditor(_ plan: RecurringInvestmentPlan?) {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: .now)
        planAmount = plan?.amount
        planFrequency = plan?.frequency ?? .monthly
        planWeekday = plan?.selectedWeekday ?? .monday
        planDayOfMonth = plan?.dayOfMonth ?? min(day, 31)
        planNextDate = plan?.nextDate ?? nextRecurringDate(onOrAfter: .now, frequency: plan?.frequency ?? .monthly, weekday: plan?.selectedWeekday ?? .monday, dayOfMonth: min(day, 31))
        planIsEnabled = plan?.isEnabled ?? true
        planNote = plan?.note ?? ""
        showingRecurringPlanEditor = true
    }

    private func saveRecurringPlan() {
        guard let amount = planAmount, amount > 0 else { return }
        let normalizedNextDate = nextRecurringDate(onOrAfter: planNextDate, frequency: planFrequency, weekday: planWeekday, dayOfMonth: planDayOfMonth)
        if let plan = asset.primaryRecurringInvestmentPlan {
            plan.amount = amount
            plan.frequency = planFrequency
            plan.selectedWeekday = planWeekday
            plan.dayOfMonth = planDayOfMonth
            plan.nextDate = normalizedNextDate
            plan.isEnabled = planIsEnabled
            plan.note = planNote
            plan.updatedAt = .now
        } else {
            let plan = RecurringInvestmentPlan(
                amount: amount,
                frequency: planFrequency,
                weekday: planWeekday,
                dayOfMonth: planDayOfMonth,
                nextDate: normalizedNextDate,
                isEnabled: planIsEnabled,
                note: planNote
            )
            plan.asset = asset
            modelContext.insert(plan)
        }
        asset.updatedAt = .now
        try? modelContext.save()
    }

    private func isRecurringPlanDue(_ plan: RecurringInvestmentPlan) -> Bool {
        guard plan.isEnabled else { return false }
        return Calendar.current.startOfDay(for: plan.nextDate) <= Calendar.current.startOfDay(for: .now)
    }

    private func recurringPlanScheduleText(_ plan: RecurringInvestmentPlan) -> String {
        switch plan.frequency {
        case .daily:
            return "每日"
        case .weekly:
            return "每周 \(plan.selectedWeekday.title)"
        case .monthly:
            return "每月 \(plan.dayOfMonth) 日"
        }
    }

    private func nextRecurringDate(after date: Date, for plan: RecurringInvestmentPlan) -> Date {
        nextRecurringDate(after: date, frequency: plan.frequency, weekday: plan.selectedWeekday, dayOfMonth: plan.dayOfMonth)
    }

    private func nextRecurringDate(after date: Date, frequency: RecurringInvestmentFrequency, weekday: Weekday, dayOfMonth: Int) -> Date {
        switch frequency {
        case .daily:
            return Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return nextWeeklyDate(after: date, weekday: weekday)
        case .monthly:
            return nextMonthlyDate(after: date, dayOfMonth: dayOfMonth)
        }
    }

    private func nextRecurringDate(onOrAfter date: Date, frequency: RecurringInvestmentFrequency, weekday: Weekday, dayOfMonth: Int) -> Date {
        switch frequency {
        case .daily:
            return date
        case .weekly:
            return nextWeeklyDate(onOrAfter: date, weekday: weekday)
        case .monthly:
            return nextMonthlyDate(onOrAfter: date, dayOfMonth: dayOfMonth)
        }
    }

    private func nextWeeklyDate(after date: Date, weekday: Weekday) -> Date {
        let calendar = Calendar.current
        var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        while calendar.component(.weekday, from: next) != weekday.rawValue {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
        }
        return next
    }

    private func nextWeeklyDate(onOrAfter date: Date, weekday: Weekday) -> Date {
        let calendar = Calendar.current
        var next = date
        while calendar.component(.weekday, from: next) != weekday.rawValue {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
        }
        return next
    }

    private func nextMonthlyDate(after date: Date, dayOfMonth: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .month, value: 1, to: date) ?? date
        return monthlyDate(containing: base, dayOfMonth: dayOfMonth)
    }

    private func nextMonthlyDate(onOrAfter date: Date, dayOfMonth: Int) -> Date {
        let calendar = Calendar.current
        let currentMonthDate = monthlyDate(containing: date, dayOfMonth: dayOfMonth)
        if calendar.startOfDay(for: currentMonthDate) >= calendar.startOfDay(for: date) {
            return currentMonthDate
        }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: date) ?? date
        return monthlyDate(containing: nextMonth, dayOfMonth: dayOfMonth)
    }

    private func monthlyDate(containing date: Date, dayOfMonth: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: date)
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 28
        components.day = max(1, min(days, dayOfMonth))
        return calendar.date(from: components) ?? date
    }

    private func cumulativeReturnRate() -> String? {
        guard performance.costValue > 0 else { return nil }
        let rate = performance.cumulativeProfitLoss / performance.costValue
        let prefix = rate > 0 ? "+" : ""
        return prefix + FinanceFormatters.percent(rate)
    }

    private var quantityTitle: String {
        switch asset.type {
        case .stock: "持仓数量"
        case .fund: "基金份额"
        case .wealthProduct: "本金"
        case .cash: "现金余额"
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    let tint: Color

    init(_ title: String, _ value: String, tint: Color = .primary) {
        self.title = title
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }
}
