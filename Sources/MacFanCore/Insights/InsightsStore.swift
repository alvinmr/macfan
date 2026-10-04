import Foundation

/// Everything Insights remembers between launches.
public struct InsightsData: Codable, Hashable, Sendable {
    public static let momentRetention: TimeInterval = 30 * 24 * 3600

    /// Newest first.
    public private(set) var moments: [HotMoment] = []
    public var cooling = CoolingLog()

    public init() {}

    public mutating func add(_ moment: HotMoment) {
        moments.insert(moment, at: 0)
        let cutoff = moment.end.addingTimeInterval(-Self.momentRetention)
        moments.removeAll { $0.end < cutoff }
    }

    public mutating func clearMoments() {
        moments = []
    }
}

/// Reads and writes `InsightsData` as one small JSON file. A file that can't be read is
/// treated as empty rather than an error: losing history is better than refusing to start.
public struct InsightsFile: Sendable {
    public let url: URL

    public init(url: URL = InsightsFile.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "MacFan/insights.json")
    }

    public func load() -> InsightsData {
        guard let data = try? Data(contentsOf: url),
              let insights = try? JSONDecoder().decode(InsightsData.self, from: data)
        else { return InsightsData() }
        return insights
    }

    public func save(_ insights: InsightsData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(insights).write(to: url, options: .atomic)
    }
}
