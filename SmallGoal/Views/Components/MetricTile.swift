import SwiftUI

struct MetricTile: View {
    let title: String
    let value: String
    let tint: Color
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(tint)
                        .monospacedDigit()
                }
            }
            Text(value)
                .font(.headline)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
