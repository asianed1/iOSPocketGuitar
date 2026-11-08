import SwiftUI

@main
struct PocketGuitarApp: App {
    @StateObject private var perf = Performer()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            TabView {
                PlayView().tabItem { Label("Play", systemImage: "music.note") }
                SetupView().tabItem { Label("Setup", systemImage: "slider.horizontal.3") }
                HelpView().tabItem { Label("How to Play", systemImage: "questionmark.circle") }
            }
            .environmentObject(perf)
            .tint(amber)
            .preferredColorScheme(.dark)
            .onAppear { perf.lifecycle(true) }
            .onChange(of: phase) { perf.lifecycle($0 == .active) }
        }
    }
}
