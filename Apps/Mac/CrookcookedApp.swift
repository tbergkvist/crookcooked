import SwiftUI

@main
struct CrookcookedApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("crookcooked") {
            DashboardView(model: model)
                .frame(minWidth: 840, minHeight: 680)
        }

        MenuBarExtra("crookcooked", systemImage: model.menuBarIcon) {
            VStack(alignment: .leading, spacing: 10) {
                Label(model.statusLabel, systemImage: model.menuBarIcon)
                Text(model.configuration.audibleAlarm ? "alarm will sound" : "quiet mode")
                    .font(.caption)
                Divider()
                if model.status == .disarmed {
                    Button("Arm & lock") { model.arm() }
                } else if model.status == .arming {
                    Button("Disarm") { model.disarm() }
                } else {
                    Text("Unlock macOS or disarm from iPhone")
                        .font(.caption)
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(8)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit crookcooked") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                .disabled(model.status != .disarmed)
            }
        }
    }
}
