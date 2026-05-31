import SwiftData
import SwiftUI

@main
struct SmallGoalApp: App {
    @StateObject private var quoteRefreshService = QuoteRefreshService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Asset.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(quoteRefreshService)
        }
        .modelContainer(sharedModelContainer)
    }
}
