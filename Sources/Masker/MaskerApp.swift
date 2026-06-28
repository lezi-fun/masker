import SwiftUI
import MaskerCore

@main
struct MaskerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 640, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Global app state shared across views
class AppState: ObservableObject {
    let detector = SensitiveDetector()
    let store = MappingStore()
    let fileExtractor = FileExtractor()
#if !NO_AI
    let aiDetector = PrivacyFilterRunner()
#endif
}
