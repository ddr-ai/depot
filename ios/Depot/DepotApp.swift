import SwiftUI

@main
struct DepotApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(DepotColor.fg)
        }
    }
}
