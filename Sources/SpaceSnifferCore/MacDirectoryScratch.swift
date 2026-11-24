import Darwin

/// One spare per native thread, removed while borrowed. Reentrant reads get a
/// different buffer; a thread exit destroys its spare through the pthread key.
enum MacDirectoryScratch {
    static let byteCount = 64 * 1024
    private final class Storage {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 8)
        deinit { pointer.deallocate() }
    }
    private static let key: pthread_key_t? = {
        var value = pthread_key_t()
        guard pthread_key_create(&value, { raw in
            Unmanaged<Storage>.fromOpaque(raw).release()
        }) == 0 else { return nil }
        return value
    }()
    static func withBuffer<Value>(_ body: (UnsafeMutableRawPointer) throws -> Value) rethrows -> Value {
        let storage: Storage
        if let key, let cached = pthread_getspecific(key), pthread_setspecific(key, nil) == 0 {
            storage = Unmanaged<Storage>.fromOpaque(cached).takeRetainedValue()
        } else { storage = Storage() }
        defer {
            if let key, pthread_getspecific(key) == nil {
                let retained = Unmanaged.passRetained(storage)
                if pthread_setspecific(key, retained.toOpaque()) != 0 { retained.release() }
            }
        }
        return try body(storage.pointer)
    }
}
