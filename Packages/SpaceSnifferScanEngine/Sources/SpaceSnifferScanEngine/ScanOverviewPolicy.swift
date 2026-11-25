/// Shared native progress contract. Each item kind retains this many candidates
/// per size mode; adapters transmit their deduplicated union, never a smaller prefix.
public enum ScanOverviewPolicy {
    public static let candidateLimit = 16
    public static let wireVersion = 1
}
