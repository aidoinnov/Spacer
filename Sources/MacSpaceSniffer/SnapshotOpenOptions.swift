import AppKit
import SpaceSnifferCore

/// Native file-open choices. Codec/Windows pathname semantics stay in Core.
@MainActor enum SnapshotOpenOptions {
    static func legacyCodePage() -> UInt32? {
        let choices: [(String, UInt32)] = [
            ("한국어 (Windows 949)", 949), ("일본어 (Windows 932)", 932),
            ("중국어 간체 (Windows 936)", 936), ("중국어 번체 (Windows 950)", 950),
            ("서유럽 (Windows 1252)", 1252), ("중부 유럽 (Windows 1250)", 1250),
            ("키릴 문자 (Windows 1251)", 1251), ("그리스어 (Windows 1253)", 1253),
            ("터키어 (Windows 1254)", 1254), ("히브리어 (Windows 1255)", 1255),
            ("아랍어 (Windows 1256)", 1256), ("발트어 (Windows 1257)", 1257),
            ("베트남어 (Windows 1258)", 1258), ("태국어 (Windows 874)", 874), ("UTF-8", 65001)]
        let alert = NSAlert(); alert.messageText = "이전 Windows 스냅샷의 인코딩"
        alert.informativeText = "이 파일에는 이름 인코딩 정보가 없습니다. 스냅샷을 저장한 Windows에서 사용한 인코딩을 선택하세요."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28))
        popup.addItem(withTitle: "인코딩 선택…")
        for (title, _) in choices { popup.addItem(withTitle: title) }
        alert.accessoryView = popup; alert.addButton(withTitle: "열기"); alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn, popup.indexOfSelectedItem > 0 else { return nil }
        return choices[popup.indexOfSelectedItem - 1].1
    }
    static func root(_ roots: [SNSSnapshot.RootInfo]) -> Int? {
        let alert = NSAlert(); alert.messageText = "스냅샷에서 열 위치 선택"
        alert.informativeText = "이 파일에는 여러 위치가 저장되어 있습니다. 이 창에서 살펴볼 위치를 선택하세요."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 480, height: 28))
        for root in roots { popup.addItem(withTitle: "\(root.path) · \(formattedBytes(root.allocatedBytes))") }
        alert.accessoryView = popup; alert.addButton(withTitle: "열기"); alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn, roots.indices.contains(popup.indexOfSelectedItem) else { return nil }
        return roots[popup.indexOfSelectedItem].index
    }
}
