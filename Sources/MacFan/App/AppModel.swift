import AppKit
import MacFanCore
import Observation
import os

/// The single source of truth for the UI. Polls the hardware, drives fan control,
/// alerts and logging, and reacts to sleep/wake and termination.
@Observable
final class AppModel {
    static let shared = AppModel()

    let preferences = Preferences()
    let helper = HelperManager()
    let updates = UpdateManager()
    let cooling: FanControlEngine

    private(set) var snapshot = HardwareSnapshot.empty
    private(set) var history = HistoryStore()
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    private(set) var hasStarted = false

    @ObservationIgnored private let monitor = HardwareMonitor()
    @ObservationIgnored private let alerts = AlertCenter()
    @ObservationIgnored private let logger = CSVLogger(directory: CSVLogger.defaultDirectory)
    @ObservationIgnored private let log = Logger(subsystem: "io.github.alvinmr.MacFan", category: "model")
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var pendingSleep: Task<Void, Never>?
    @ObservationIgnored private var lastLogged = Date.distantPast
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        cooling = FanControlEngine(helper: helper)
    }

    var logDirectory: URL { logger.directory }

    // MARK: Lifecycle

    func start() {
        guard loop == nil else { return }
        observeSystemEvents()
        loop = Task { [weak self] in
            await self?.helper.refresh()
            while let self, !Task.isCancelled {
                await self.tick()
                let interval = self.preferences.refreshInterval
                let sleep = Task { _ = try? await Task.sleep(for: .seconds(interval)) }
                self.pendingSleep = sleep
                await sleep.value
            }
        }
    }

    /// Runs the next tick now instead of waiting — so a mode change takes effect immediately.
    func refreshNow() {
        pendingSleep?.cancel()
    }

    func prepareForTermination() {
        loop?.cancel()
        cooling.shutdown()
        Task { await logger.close() }
    }

    // MARK: Derived state

    var summaries: [CategorySummary] {
        snapshot.summaries(includeUnidentified: preferences.showsUnidentifiedSensors)
    }

    var visibleReadings: [SensorReading] {
        snapshot.readings
            .filter { preferences.showsUnidentifiedSensors || $0.sensor.isIdentified }
            .sorted(by: SensorReading.displayOrder)
    }

    var status: ThermalStatus {
        ThermalStatus(snapshot: snapshot, thermalState: thermalState, hasStarted: hasStarted)
    }

    /// What the menu bar shows: the chosen sensor, else the hottest CPU.
    var menuBarReading: SensorReading? {
        preferences.menuBarSensorID.flatMap(snapshot.reading(id:)) ?? snapshot.hottest(in: [.cpu]) ?? snapshot.hottest()
    }

    var fastestFanRPM: Double? {
        snapshot.fans.map(\.currentRPM).max()
    }

    // MARK: Tick

    private func tick() async {
        let snapshot = await monitor.snapshot()
        self.snapshot = snapshot
        history.record(snapshot)
        thermalState = ProcessInfo.processInfo.thermalState
        hasStarted = true

        await cooling.update(settings: preferences.cooling, snapshot: snapshot)
        alerts.evaluate(snapshot, preferences: preferences, unit: preferences.unit)

        if preferences.loggingEnabled, snapshot.date.timeIntervalSince(lastLogged) >= preferences.loggingInterval {
            lastLogged = snapshot.date
            do {
                try await logger.append(snapshot)
            } catch {
                log.error("CSV logging failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Actions

    func setCoolingMode(_ mode: CoolingMode) {
        preferences.cooling.mode = mode
        refreshNow()
    }

    func enableAlerts(_ enabled: Bool) async {
        if enabled {
            preferences.alertsEnabled = await alerts.requestAuthorization()
        } else {
            preferences.alertsEnabled = false
        }
    }

    func applyDockIconPreference() {
        NSApp.setActivationPolicy(preferences.showsDockIcon ? .regular : .accessory)
    }

    func rediscoverSensors() {
        Task {
            await monitor.discover()
            refreshNow()
        }
    }

    // MARK: System events

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let model = AppModel.shared
                Task { await model.cooling.suspend() }
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let model = AppModel.shared
                model.cooling.resume()
                model.refreshNow()
            }
        })
        // Picks up approval in System Settings → Login Items as soon as the user comes back.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let model = AppModel.shared
                Task { await model.helper.refresh() }
            }
        })
    }
}
