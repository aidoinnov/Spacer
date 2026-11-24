import Foundation
#if os(Windows)
import WinSDK
#else
import CoreFoundation
#endif

/// OS encoding services sit behind this adapter; import grammar never guesses ACP.
enum LegacyCodePageDecoder {
    static func decode(_ data: Data, page: UInt32) throws -> String {
        #if os(Windows)
        guard IsValidCodePage(page), data.count <= Int(Int32.max) else { throw WindowsLegacyText.DecodeError.unsupportedCodePage(page) }
        if data.isEmpty { return "" }
        return try data.withUnsafeBytes { bytes in
            let input = bytes.baseAddress!.assumingMemoryBound(to: CChar.self)
            let count = MultiByteToWideChar(page, DWORD(MB_ERR_INVALID_CHARS), input, Int32(data.count), nil, 0)
            guard count > 0 else { throw WindowsLegacyText.DecodeError.invalidText }
            var units = [WCHAR](repeating: 0, count: Int(count))
            let written = units.withUnsafeMutableBufferPointer { output in
                MultiByteToWideChar(page, DWORD(MB_ERR_INVALID_CHARS), input, Int32(data.count), output.baseAddress, count)
            }
            guard written == count else { throw WindowsLegacyText.DecodeError.invalidText }
            return String(decoding: units, as: UTF16.self)
        }
        #else
        let cf = CFStringConvertWindowsCodepageToEncoding(page)
        guard cf != kCFStringEncodingInvalidId else { throw WindowsLegacyText.DecodeError.unsupportedCodePage(page) }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        guard let value = String(data: data, encoding: encoding) else { throw WindowsLegacyText.DecodeError.invalidText }
        return value
        #endif
    }
}
