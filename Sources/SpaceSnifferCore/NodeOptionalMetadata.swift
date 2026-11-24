import Foundation

/// Presence bits share one scalar block; zero/NaN/distant dates remain actual
/// values when present. Clearing a field resets its storage for value equality.
struct NodeOptionalMetadata: Sendable, Equatable {
    private var createdValue = Date.distantPast
    private var accessedValue = Date.distantPast
    private var ownValue: Int64 = 0
    private var attributesValue: UInt32 = 0
    private var flagsValue: UInt8 = 0
    private var typeValue: UInt8 = 0
    private var present: UInt8 = 0
    private mutating func mark(_ bit: UInt8, _ exists: Bool) { if exists { present |= bit } else { present &= ~bit } }
    var created: Date? {
        get { present & 1 != 0 ? createdValue : nil }
        set { createdValue = newValue ?? .distantPast; mark(1, newValue != nil) }
    }
    var accessed: Date? {
        get { present & 2 != 0 ? accessedValue : nil }
        set { accessedValue = newValue ?? .distantPast; mark(2, newValue != nil) }
    }
    var ownAllocatedBytes: Int64? {
        get { present & 4 != 0 ? ownValue : nil }
        set { ownValue = newValue ?? 0; mark(4, newValue != nil) }
    }
    var nativeAttributes: UInt32? {
        get { present & 8 != 0 ? attributesValue : nil }
        set { attributesValue = newValue ?? 0; mark(8, newValue != nil) }
    }
    var nativeFlags: UInt8? {
        get { present & 16 != 0 ? flagsValue : nil }
        set { flagsValue = newValue ?? 0; mark(16, newValue != nil) }
    }
    var nativeType: UInt8? {
        get { present & 32 != 0 ? typeValue : nil }
        set { typeValue = newValue ?? 0; mark(32, newValue != nil) }
    }
}
