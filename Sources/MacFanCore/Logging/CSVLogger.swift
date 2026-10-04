import Foundation

/// Appends snapshots to one CSV file per day, e.g. `macfan-2026-10-04.csv`.
/// A new header row is written whenever the set of sensors or fans changes.
public actor CSVLogger {
    public nonisolated let directory: URL
    private var handle: FileHandle?
    private var currentDay: String?
    private var columns: [String] = []

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "MacFan", directoryHint: .isDirectory)
            .appending(path: "Logs", directoryHint: .isDirectory)
    }

    public func append(_ snapshot: HardwareSnapshot) throws {
        let day = Self.dayFormatter.string(from: snapshot.date)
        if day != currentDay {
            try openFile(for: day)
        }

        let readings = snapshot.readings.sorted { $0.id < $1.id }
        let fans = snapshot.fans.sorted { $0.index < $1.index }
        let header = ["time"] + readings.map { "\($0.sensor.name) (°C)" } + fans.map { "\($0.name) (rpm)" }
        if header != columns {
            columns = header
            try write(row: header)
        }

        let time = snapshot.date.formatted(.iso8601)
        let temperatures = readings.map { String(format: "%.1f", $0.celsius) }
        let speeds = fans.map { String(Int($0.currentRPM.rounded())) }
        try write(row: [time] + temperatures + speeds)
    }

    public func close() {
        try? handle?.close()
        handle = nil
        currentDay = nil
        columns = []
    }

    private func openFile(for day: String) throws {
        close()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "macfan-\(day).csv")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        self.handle = handle
        currentDay = day
    }

    private func write(row: [String]) throws {
        let line = row.map(Self.escape).joined(separator: ",") + "\n"
        try handle?.write(contentsOf: Data(line.utf8))
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
