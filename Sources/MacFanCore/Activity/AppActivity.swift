import Darwin
import Foundation

/// CPU time a process has used so far.
public struct ProcessSample: Hashable, Sendable {
    public let pid: Int32
    /// Path of the executable, e.g. `/Applications/Safari.app/Contents/MacOS/Safari`.
    public let path: String
    public let cpuNanoseconds: UInt64

    public init(pid: Int32, path: String, cpuNanoseconds: UInt64) {
        self.pid = pid
        self.path = path
        self.cpuNanoseconds = cpuNanoseconds
    }
}

/// CPU time used by the whole Mac so far, in scheduler ticks summed over every core.
public struct CPULoad: Hashable, Sendable {
    public let busyTicks: UInt64
    public let totalTicks: UInt64
    public let cores: Int

    public init(busyTicks: UInt64, totalTicks: UInt64, cores: Int) {
        self.busyTicks = busyTicks
        self.totalTicks = totalTicks
        self.cores = cores
    }
}

/// An app and how hard it is working the CPU right now.
public struct AppActivity: Identifiable, Hashable, Sendable {
    public static let systemID = "system"

    /// The app bundle's path, or the executable's for command-line tools.
    public let id: String
    public let name: String
    /// For the app's icon. `nil` for command-line tools.
    public let bundlePath: String?
    /// Share of one core, like Activity Monitor: 200 means two cores flat out.
    public let cpuPercent: Double

    public init(id: String, name: String, bundlePath: String?, cpuPercent: Double) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.cpuPercent = cpuPercent
    }

    /// Everything macOS won't itemize for us: the kernel, WindowServer, other users' processes.
    public var isSystem: Bool { id == Self.systemID }
}

/// Turns successive process samples into per-app CPU usage. Helper processes count
/// toward the app that contains them, so "Google Chrome" shows up once, not as forty helpers.
public struct ActivityTracker: Sendable {
    private var previous: (date: Date, cpu: [Int32: UInt64], load: CPULoad?)?

    public init() {}

    /// Busiest first. `nil` on the first call, which only sets the baseline.
    ///
    /// macOS only shares per-process CPU time for the user's own processes. With the
    /// whole Mac's `load`, the rest is reported as one `AppActivity.isSystem` entry, so
    /// a busy WindowServer or kernel still shows up.
    public mutating func update(_ samples: [ProcessSample], load: CPULoad? = nil, at date: Date) -> [AppActivity]? {
        defer { previous = (date, Dictionary(samples.map { ($0.pid, $0.cpuNanoseconds) }, uniquingKeysWith: { $1 }), load) }
        guard let previous, date > previous.date else { return nil }
        let elapsed = date.timeIntervalSince(previous.date) * 1_000_000_000

        var usage: [String: (name: String, bundlePath: String?, nanoseconds: Double)] = [:]
        for sample in samples {
            // A process that started since the last sample used all its time in between.
            let before = previous.cpu[sample.pid] ?? 0
            guard sample.cpuNanoseconds > before else { continue }
            let owner = Self.owner(ofExecutable: sample.path)
            usage[owner.id, default: (owner.name, owner.bundlePath, 0)].nanoseconds += Double(sample.cpuNanoseconds - before)
        }
        var apps = usage.map {
            AppActivity(id: $0.key, name: $0.value.name, bundlePath: $0.value.bundlePath, cpuPercent: $0.value.nanoseconds / elapsed * 100)
        }
        if let load, let before = previous.load, load.totalTicks > before.totalTicks, load.busyTicks >= before.busyTicks {
            let total = Double(load.busyTicks - before.busyTicks) / Double(load.totalTicks - before.totalTicks) * Double(load.cores) * 100
            // Ticks and process times are read a moment apart, so small differences are noise.
            let rest = total - apps.map(\.cpuPercent).reduce(0, +)
            if rest >= 1 {
                apps.append(AppActivity(id: AppActivity.systemID, name: "macOS", bundlePath: nil, cpuPercent: rest))
            }
        }
        return apps.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    /// The outermost `.app` bundle containing the executable, so helpers inside
    /// `Foo.app/Contents/Frameworks/…` belong to Foo.
    public static func owner(ofExecutable path: String) -> (id: String, name: String, bundlePath: String?) {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        if let index = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            let bundle = components[...index].joined(separator: "/")
            return (bundle, String(components[index].dropLast(4)), bundle)
        }
        return (path, String(components.last ?? Substring(path)), nil)
    }
}

/// Reads CPU time for every process the user owns, through `libproc`. Needs no privileges;
/// other users' and system processes are skipped because macOS won't share them.
///
/// Not thread-safe; `ActivityMonitor` owns it.
final class ProcessReader {
    private var paths: [Int32: String] = [:]
    /// Each `mach_host_self()` call adds a port reference, so take one and keep it.
    private let host = mach_host_self()
    /// `ri_user_time` and `ri_system_time` are in Mach time units, which aren't nanoseconds on Apple Silicon.
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    func sample() -> [ProcessSample] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [Int32](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<Int32>.size)))
        guard count > 0 else { return [] }

        var samples: [ProcessSample] = []
        var seen: [Int32: String] = [:]
        for pid in pids.prefix(min(count, capacity)) where pid > 0 {
            guard let ticks = cpuTicks(of: pid), let path = paths[pid] ?? path(of: pid) else { continue }
            seen[pid] = path
            samples.append(ProcessSample(pid: pid, path: path, cpuNanoseconds: ticks * timebase.numer / timebase.denom))
        }
        paths = seen
        return samples
    }

    func load() -> CPULoad? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        let user = UInt64(ticks.0), system = UInt64(ticks.1), idle = UInt64(ticks.2), nice = UInt64(ticks.3)
        return CPULoad(busyTicks: user + system + nice, totalTicks: user + system + idle + nice,
                       cores: ProcessInfo.processInfo.activeProcessorCount)
    }

    private func cpuTicks(of pid: Int32) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return result == 0 ? info.ri_user_time + info.ri_system_time : nil
    }

    private func path(of pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(length), as: UTF8.self)
    }
}

/// Which apps are keeping the CPU busy. Sampling walks every process, so callers should
/// only ask while someone is looking at the answer.
public actor ActivityMonitor {
    private let reader = ProcessReader()
    private var tracker = ActivityTracker()

    public init() {}

    public func sample(at date: Date = Date()) -> [AppActivity]? {
        let load = reader.load()
        return tracker.update(reader.sample(), load: load, at: date)
    }

    /// Forgets the baseline, so stale totals aren't averaged over a long pause.
    public func reset() {
        tracker = ActivityTracker()
    }
}
