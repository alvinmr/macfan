import AppKit
import Foundation
import os
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
        case unavailable(String)
    }

    private(set) var status: Status = .unknown
    private(set) var lastError: String?

    var isReady: Bool { status == .ready }

    @ObservationIgnored private var connection: NSXPCConnection?
    private var service: SMAppService { .daemon(plistName: HelperConstants.daemonPlistName) }

    // MARK: Lifecycle

    func refresh() async {
        // A responding helper wins over whatever SMAppService says: it also covers
        // helpers installed manually with `scripts/install-helper-dev.sh`.
        if let version = try? await protocolVersion() {
            status = version == HelperConstants.protocolVersion ? .ready : .outdated
            return
        }
        switch service.status {
        case .enabled:
            status = .unavailable(String(localized: "The helper is registered but isn't responding. Restart your Mac, or see Troubleshooting in the README."))
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

    /// Blocks for at most `timeout`. Only for app termination, where async work can't finish.
    func restoreSystemControlBlocking(timeout: TimeInterval = 2) {
        guard isReady else { return }
        let done = DispatchSemaphore(value: 0)
        let proxy = activeConnection().synchronousRemoteObjectProxyWithErrorHandler { @Sendable _ in done.signal() }
        (proxy as? MacFanHelperProtocol)?.restoreSystemControl { _ in done.signal() }
        _ = done.wait(timeout: .now() + timeout)
    }

    // MARK: XPC plumbing

    private func call<T: Sendable>(
        _ body: (MacFanHelperProtocol, @escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let connection = activeConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable error in
                gate.resume(with: .failure(error))
            }
            guard let helper = proxy as? MacFanHelperProtocol else {
                gate.resume(with: .failure(CocoaError(.featureUnsupported)))
                return
            }
            body(helper) { gate.resume(with: $0) }
        }
    }

    private func activeConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: MacFanHelperProtocol.self)
        // XPC calls handlers on its own queue. They must be @Sendable, or Swift infers
        // main-actor isolation from this context and traps at runtime when they run.
        connection.invalidationHandler = { @Sendable [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

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
