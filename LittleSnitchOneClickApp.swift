import SwiftUI
import AppKit

@main
struct LittleSnitchOneClickApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ZStack {
                ContentView()
                    .environmentObject(model)
                MainWindowRegistrationView()
                    .environmentObject(model)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(minWidth: 660, minHeight: 520)
        }
    }
}

private struct MainWindowRegistrationView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var model: AppModel

    var body: some View {
        Color.clear
            .onAppear {
                model.registerOpenMainWindowHandler {
                    openWindow(id: "main")
                }
            }
    }
}
