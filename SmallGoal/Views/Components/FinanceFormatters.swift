import SwiftUI

enum FinanceFormatters {
    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "CNY").precision(.fractionLength(2)))
    }

    static func signedCurrency(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + currency(value)
    }

    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(2)))
    }

    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    static func profitColor(_ value: Double) -> Color {
        if value > 0 { return .red }
        if value < 0 { return .green }
        return .secondary
    }
}

extension View {
    func sectionCard() -> some View {
        padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
