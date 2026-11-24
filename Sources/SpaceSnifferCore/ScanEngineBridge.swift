import SpaceSnifferScanEngine

// Existing Core clients keep their API while the implementation has one owner.
public typealias ScanControl = SpaceSnifferScanEngine.ScanControl
typealias ScanPublication = SpaceSnifferScanEngine.ScanPublication
typealias ObservedByteBatch = SpaceSnifferScanEngine.ObservedByteBatch
typealias DirectoryIOBudget = SpaceSnifferScanEngine.DirectoryIOBudget
typealias DirectoryReadTicket = SpaceSnifferScanEngine.DirectoryReadTicket<DirectoryReadOutput>
typealias DirectoryReadOutput = SpaceSnifferScanEngine.DirectoryReadOutput<OrderedDirectoryListing, ScanIOStatistics>
