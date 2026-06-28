import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 1  // default to Guide (1), tabs reordered: 0=sanitize, 1=guide, 2=restore

    var body: some View {
        TabView(selection: $selectedTab) {
            SanitizeView()
                .tabItem {
                    Label("脱敏", systemImage: "lock.shield")
                }
                .tag(0)

            GuideView()
                .tabItem {
                    Label("使用指南", systemImage: "book.fill")
                }
                .tag(1)

            RestoreView()
                .tabItem {
                    Label("还原", systemImage: "lock.shield.fill")
                }
                .tag(2)
        }
        .padding()
    }
}
