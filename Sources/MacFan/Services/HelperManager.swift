import AppKit
import Foundation
import os
import MacFanCore
import MacFanXPC
import Observation
import ServiceManagement

/// Installs the privileged helper and talks to it over XPC.
///
/// Reading temperatures never needs the helper; only changing fan speed does.
@Observable
final class HelperManager {
    enum Status: Equatable {
        case unknown
        case notInstalled
        /// Registered, waiting for the user to allow it in System Settings → Login Items.
        case requiresApproval
        case ready
        /// Installed, but speaks an older protocol than this app.
        case outdated
        /// Registered, but macOS won't start the helper that came with an update. Ad-hoc
        /// signed helpers are trusted by their exact code hash, and launchd keeps the
        /// constraint recorded for the previous build until the job is removed or the Mac
        /// restarts. `resetAndReinstall()` fixes it without a restart.
        case staleAfterUpdate
        case unavailable(String)
    }

    private(set) var status: Status = .unknown
    private(set) var lastError: String?

    var isReady: Bool { status == .ready }

    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The app build the helper last answered for. When it differs from the running build,
    /// a silent helper is almost always the one an update replaced.
    private var lastWorkingBuild: String? {
        get { defaults.string(forKey: "helperLastWorkingBuild") }
        set { defaults.set(newValue, forKey: "helperLastWorkingBuild") }
    }

    private static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    private var service: SMAppService { .daemon(plistName: HelperConstants.daemonPlistName) }

    // MARK: Lifecycle

    func refresh() async {
        // A responding helper wins over whatever SMAppService says: it also covers
        // helpers installed manually with `scripts/install-helper-dev.sh`.
        if let version = try? await protocolVersion() {
            status = version == HelperConstants.protocolVersion ? .ready : .outdated
            if status == .ready { lastWorkingBuild = Self.currentBuild }
            return
        }
        switch service.status {
        case .enabled:
            // Unknown history counts as an update: helpers installed before this check
            // existed hit the same restart requirement on their first update.
            if lastWorkingBuild != Self.currentBuild {
                status = .staleAfterUpdate
            } else {
                status = .unavailable(String(localized: "The helper is registered but isn't responding. Restart your Mac, or see the FAQ in MacFan's README."))
            }
        case .requiresApproval:
            status = .requiresApproval
        case .notRegistered, .notFound:
            status = .notInstalled
        @unknown default:
            status = .notInstalled
        }
    }

    func install() async {
        lastError = nil
        do {
            if status == .outdated || service.status == .enabled {
                try? await service.unregister()
            }
            try service.register()
        } catch {
            // Registration "fails" when approval is still pending; status tells the real story.
            lastError = error.localizedDescription
        }
        try? await Task.sleep(for: .milliseconds(300))
        await refresh()
        if status == .requiresApproval {
            lastError = nil
            openLoginItemsSettings()
        }
    }

    func uninstall() async {
        await restoreSystemControlIgnoringErrors()
        connection?.invalidate()
        connection = nil
        try? await service.unregister()
        await refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Removes the helper's launchd job (macOS asks for an administrator password), then
    /// registers it again, so launchd records the helper that's in the app now. Fixes
    /// `.staleAfterUpdate` without a restart.
    func resetAndReinstall() async {
        lastError = nil
        connection?.invalidate()
        connection = nil
        // The label is a compile-time constant, so nothing user-controlled reaches the shell.
        let command = "launchctl bootout system/\(HelperConstants.helperLabel) || true"
        let script = "do shell script \"\(command)\" with administrator privileges with prompt \"\(String(localized: "MacFan needs to reset its fan control helper after the update."))\""
        switch await Self.runAppleScript(script) {
        case .success:
            await install()
        case .cancelled:
            await refresh()
        case .failed(let message):
            lastError = message
            await refresh()
        }
    }

    /// Shows macOS's own "Are you sure you want to restart?" dialog, so nothing restarts
    /// without the user confirming and every app gets the chance to save.
    func requestRestart() {
        NSAppleScript(source: "tell application \"loginwindow\" to «event aevtrrst»")?.executeAndReturnError(nil)
    }

    private enum ScriptResult { case success, cancelled, failed(String) }

    /// Runs `osascript` as a child process so the password dialog never blocks the main thread.
    private static func runAppleScript(_ source: String) async -> ScriptResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let errors = Pipe()
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { @Sendable process in
                let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success)
                } else if output.contains("-128") {
                    continuation.resume(returning: .cancelled)   // the user clicked Cancel
                } else {
                    continuation.resume(returning: .failed(output.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failed(error.localizedDescription))
            }
        }
    }

    // MARK: Commands

    func protocolVersion() async throws -> String {
        try await call { proxy, done in
            proxy.protocolVersion { done(.success($0)) }
        }
    }

    func setTarget(rpm: Double, fanIndex: Int) async throws {
        try await call { proxy, done in
            proxy.setTargetRPM(rpm, fanIndex: fanIndex) { error in
                done(error.map { .failure($0) } ?? .success(()))
            }
        }
    }

    func restoreSystemControl() async throws {
        try await call { proxy, done in
            proxy.restoreSystemControl { error in
                done(error.map { .failure($0) } ?? .success(()))
            }
        }
    }

    func restoreSystemControlIgnoringErrors() async {
        try? await restoreSystemControl()
    }

    /// Blocks for at most two seconds. Only for app termination, where async work can't finish.
    ///
    /// Uses the *asynchronous* proxy on purpose: its reply and error handlers run on XPC's
    /// own queue, so the main thread can wait on the semaphore with a real deadline. A
    /// synchronous proxy would block inside the call itself, before any timeout applied.
    func restoreSystemControlBlocking() {
        guard isReady else { return }
        let done = DispatchSemaphore(value: 0)
        let proxy = activeConnection().remoteObjectProxyWithErrorHandler { @Sendable _ in done.signal() }
        (proxy as? MacFanHelperProtocol)?.restoreSystemControl { @Sendable _ in done.signal() }
        _ = done.wait(timeout: .now() + 2)
    }

    // MARK: XPC plumbing

    /// Every call has a deadline: a helper that is connected but stuck must not stall the
    /// polling loop forever.
    private func call<T: Sendable>(
        timeout: Duration = .seconds(5),
        _ body: (MacFanHelperProtocol, @escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let connection = activeConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeOnce(continuation)
            let deadline = Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                gate.resume(with: .failure(HelperError.timedOut))
            }
            let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable error in
                deadline.cancel()
                gate.resume(with: .failure(error))
            }
            guard let helper = proxy as? MacFanHelperProtocol else {
                deadline.cancel()
                gate.resume(with: .failure(CocoaError(.featureUnsupported)))
                return
            }
            body(helper) { result in
                deadline.cancel()
                gate.resume(with: result)
            }
        }
    }

    private func activeConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: MacFanHelperProtocol.self)
        // XPC calls handlers on its own queue. They must be @Sendable, or Swift infers
        // main-actor isolation from this context and traps at runtime when they run.
        connection.invalidationHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.connectionLost(invalidated: true) }
        }
        connection.interruptionHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.connectionLost(invalidated: false) }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    /// The helper exited, crashed or restarted. Stop relying on it until its version is
    /// confirmed again. Only a *ready* helper triggers a re-check, so a helper that isn't
    /// installed can't cause a loop of failed connections.
    private func connectionLost(invalidated: Bool) {
        if invalidated { connection = nil }
        guard status == .ready else { return }
        status = .unknown
        Task { await refresh() }
    }
}

enum HelperError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut: String(localized: "The fan control helper didn't respond in time.")
        }
    }
}

extension HelperManager: FanCommanding {}

/// XPC can report both an error and a reply for one call, from its own queue; a
/// continuation must resume exactly once. `nonisolated` because it is never touched
/// from the main actor's point of view.
nonisolated private final class ResumeOnce<T: Sendable>: Sendable {
    private let continuation: OSAllocatedUnfairLock<CheckedContinuation<T, Error>?>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = OSAllocatedUnfairLock(initialState: continuation)
    }

    func resume(with result: Result<T, Error>) {
        let pending = continuation.withLock { state in
            defer { state = nil }
            return state
        }
        pending?.resume(with: result)
    }
}
