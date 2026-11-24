import Foundation

public enum ScanVolumeTraversal: String, Codable, Sendable {
    case selectedVolume, allVolumes
}

public struct ScanVolumeExclusion: Codable, Sendable, Equatable {
    public let path: String
    public let reason: String
    public init(path:String,reason:String) {self.path=path;self.reason=reason}
}

/// Live scan provenance. Legacy SNS files do not encode this field.
public struct ScanVolumeCoverage: Codable, Sendable, Equatable {
    public let traversal: ScanVolumeTraversal
    public var exclusions: [ScanVolumeExclusion] = []
    public var excludedCount = 0

    public init(traversal:ScanVolumeTraversal) {self.traversal=traversal}

    public mutating func exclude(_ path: String, reason: String) {
        excludedCount += 1
        if exclusions.count < 500 { exclusions.append(.init(path: path, reason: reason)) }
    }
}

