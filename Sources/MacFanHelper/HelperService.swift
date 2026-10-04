import Foundation
import MacFanXPC
import SMCKit
import os

/// Serves `MacFanHelperProtocol` as root.
///
/// Safety nets, in order of how often they matter:
/// 1. Every fan is handed back to macOS when the last client disconnects (app quit or crash).
/// 2. A watchdog does the same if the app stops sending commands for `watchdogTimeout`.
/// 3. On SIGTERM (unregister, shutdown) fans are restored before exiting.
///
/// `@unchecked Sendable` is backed by a real rule: every mutable property is read and
/// written only on the serial `queue`. XPC delivers calls on arbitrary threads, so the
/// queue — not an actor — is what serializes SMC access with the watchdog timer.
final class HelperService: NSObject, NSXPCListenerDelegate, MacFanHelperProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.github.alvinmr.MacFan.helper.smc")
    private let log = Logger(subsystem: HelperConstants.helperLabel, category: "service")
    private let clientRequirement: String

    // Everything below is only touched on `queue`.
    private var fanControl: SMCFanControl?
    private var isControlling = false
    private var lastCommand = Date.distantPast
    private var openConnections = 0
    private var watchdog: DispatchSourceTimer?

    init(clientRequirement: String) {
        self.clientRequirement = clientRequirement
        super.init()
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.checkWatchdog() }
        timer.resume()
        queue.sync { watchdog = timer }
        log.info("Helper started; client requirement: \(self.clientRequirement, privacy: .public)")
    }

    func restoreSynchronously() {
        queue.sync { restoreLocked(reason: "terminating") }
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Messages from anything not signed as MacFan are rejected by the system.
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: MacFanHelperProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in self?.connectionClosed() }
        queue.sync { openConnections += 1 }
        connection.resume()
        return true
    }

    // MARK: MacFanHelperProtocol

    func protocolVersion(withReply reply: @escaping @Sendable (String) -> Void) {
        reply(HelperConstants.protocolVersion)
    }

    func setTargetRPM(_ rpm: Double, fanIndex: Int, withReply reply: @escaping @Sendable (NSError?) -> Void) {
        queue.async { [self] in
            lastCommand = Date()
            do {
                let fans = try smcFanControl()
                guard (0..<fans.fanCount()).contains(fanIndex), rpm.isFinite else {
                    throw NSError.helper(.writeFailed, "Invalid fan \(fanIndex) or speed \(rpm)")
                }
                isControlling = true
                try fans.setTarget(rpm: rpm, fan: fanIndex)
                reply(nil)
            } catch let error as NSError where error.domain == HelperConstants.errorDomain {
                reply(error)
            } catch {
                log.error("setTarget failed: \(String(describing: error), privacy: .public)")
                reply(.helper(.writeFailed, String(describing: error)))
            }
        }
    }

    func restoreSystemControl(withReply reply: @escaping @Sendable (NSError?) -> Void) {
        queue.async { [self] in
            restoreLocked(reason: "requested")
            reply(nil)
        }
    }

    // MARK: Private (call on `queue`)

    private func smcFanControl() throws -> SMCFanControl {
        if let fanControl { return fanControl }
        do {
            let control = SMCFanControl(smc: try SMCConnection())
            fanControl = control
            return control
        } catch {
            throw NSError.helper(.smcUnavailable, String(describing: error))
        }
    }

    private func restoreLocked(reason: String) {
        isControlling = false
        lastCommand = .distantPast
        guard let fans = try? smcFanControl() else { return }
        do {
            try fans.restoreAutomatic()
            log.info("Fans returned to macOS (\(reason, privacy: .public))")
        } catch {
            log.error("Restoring fans failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func connectionClosed() {
        queue.async { [self] in
            openConnections = max(0, openConnections - 1)
            if openConnections == 0, isControlling {
                restoreLocked(reason: "client disconnected")
            }
        }
    }

    private func checkWatchdog() {
        guard isControlling, Date().timeIntervalSince(lastCommand) > HelperConstants.watchdogTimeout else { return }
        restoreLocked(reason: "watchdog: no commands for \(Int(HelperConstants.watchdogTimeout))s")
    }
}
