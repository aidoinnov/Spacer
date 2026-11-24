import Foundation

/// Explicit Windows text decoding. CP_ACP is not a Mac default or UTF8 guess.
public enum WindowsLegacyText {
    public enum DecodeError: LocalizedError, Equatable {
        case codePageRequired, unsupportedCodePage(UInt32), invalidText
        public var errorDescription: String? {
            switch self {
            case .codePageRequired: "이름을 읽으려면 저장한 Windows의 ANSI 코드 페이지를 지정하세요."
            case let .unsupportedCodePage(page): "이 환경에서 Windows 코드 페이지 \(page)을 읽을 수 없습니다."
            case .invalidText: "지정한 코드 페이지로 텍스트를 읽을 수 없습니다."
            }
        }
    }
    public static func decode(_ data: Data, codePage: UInt32?) throws -> String {
        if data.allSatisfy({ $0 < 128 }) { return String(decoding: data, as: UTF8.self) }
        guard let codePage, codePage != 0 else { throw DecodeError.codePageRequired }
        return try LegacyCodePageDecoder.decode(data, page: codePage)
    }
}

