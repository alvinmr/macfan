import Foundation
import Observation
import Sparkle

/// Self-updates through Sparkle, from the appcast on GitHub Releases.
///
/// Inert outside a real app bundle that declares a feed (`swift run`, tests), where
/// Sparkle would otherwise greet you with an error on launch.
@Observable
final class UpdateManager {
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    init(bundle: Bundle = .main) {
        let isReleaseBundle = bundle.bundleURL.pathExtension == "app"
            && bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = isReleaseBundle
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil

        // Sparkle publishes `canCheckForUpdates` via KVO on the main thread.
        canCheckObservation = controller?.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { @Sendable [weak self] _, change in
            let canCheck = change.newValue ?? false
            MainActor.assumeIsolated { self?.canCheckForUpdates = canCheck }
        }
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
