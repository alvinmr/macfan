import AppKit
import SwiftUI

@main
struct MacFanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("MacFan", id: WindowID.main) {
            RootView()
                .environment(model)
                .environment(model.preferences)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 960, height: 660)
        .windowToolbarStyle(.unified)
        .commands {
            NavigationCommands()
            CommandGroup(after: .appInfo) {
                if model.updates.isAvailable {
                    Button("Check for Updates…") { model.updates.checkForUpdates() }
                        .disabled(!model.updates.canCheckForUpdates)
                }
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
                .environment(model.preferences)
        } label: {
            MenuBarLabel()
                .environment(model)
                .environment(model.preferences)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(model.preferences)
        }
    }
}

enum WindowID {
    static let main = "main"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        model.applyDockIconPreference()
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.prepareForTermination()
    }

    /// Closing the window keeps MacFan in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
