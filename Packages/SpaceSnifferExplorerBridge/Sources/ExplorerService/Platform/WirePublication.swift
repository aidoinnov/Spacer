import Foundation
#if os(Windows)
import WinSDK
#else
import Darwin
#endif
/// The sole filesystem publication port for streamed GPUI wire files.
enum WirePublication {
    static func publish(_ temporary:URL,to destination:URL)throws {
#if os(Windows)
        let success=(Array(temporary.path.utf16)+[0]).withUnsafeBufferPointer {source in
            (Array(destination.path.utf16)+[0]).withUnsafeBufferPointer {target in
                MoveFileExW(source.baseAddress,target.baseAddress,DWORD(MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))
            }
        }
        guard success else {throw NSError(domain:"Win32",code:Int(GetLastError()))}
#else
        guard rename(temporary.path,destination.path)==0 else {throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)}
#endif
    }
}
