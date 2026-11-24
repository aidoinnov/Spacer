/// Windows composition policy. Portable scheduling never reads OS constants.
struct WindowsScanPolicy: Sendable {
    let workers: Int
    let ioLimit = 8
    let queueCapacity = 8
    let prefetchEntryLimit = 4096
    let heartbeatSeconds = 0.1
    var futureCapacity: Int { max(0, workers - 1) }
    init(workers: Int) { self.workers = min(8, max(1, workers)) }
}
