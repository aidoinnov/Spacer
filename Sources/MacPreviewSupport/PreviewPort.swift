import Foundation
import AppKit
import Quartz

/// Called only from GPUI's UI lane. AppKit keeps the panel and data source alive.
@_cdecl("space_sniffer_preview")
public func spaceSnifferPreview(_ path: UnsafePointer<CChar>) -> Int32 {
    guard Thread.isMainThread else { return 0 }
    let value = String(cString:path)
    return MainActor.assumeIsolated {
        QuickLook.shared.show(URL(fileURLWithPath:value))
        return QLPreviewPanel.shared()?.isVisible == true ? 1 : 0
    }
}

/// The view belongs to GPUI. This port changes only its native window presentation.
@_cdecl("space_sniffer_window_state")
public func spaceSnifferWindowState(_ pointer:UnsafeMutableRawPointer,_ mode:Int32)->Int32 {
    guard Thread.isMainThread else {return 0}
    let address=UInt(bitPattern:pointer)
    return MainActor.assumeIsolated {
        guard let pointer=UnsafeMutableRawPointer(bitPattern:address) else {return 0}
        let view=Unmanaged<NSView>.fromOpaque(pointer).takeUnretainedValue()
        guard let window=view.window else {return 0}
        switch mode {
        case 0:NSApp.unhide(nil);window.deminiaturize(nil);window.makeKeyAndOrderFront(nil)
        case 1:window.miniaturize(nil)
        case 2:window.orderOut(nil)
        default:return 0
        }
        return 1
    }
}

@_cdecl("space_sniffer_window_observation")
public func spaceSnifferWindowObservation(_ pointer:UnsafeMutableRawPointer)->Int32 {
    guard Thread.isMainThread else {return -1};let address=UInt(bitPattern:pointer)
    return MainActor.assumeIsolated {
        guard let pointer=UnsafeMutableRawPointer(bitPattern:address),let window=Unmanaged<NSView>.fromOpaque(pointer).takeUnretainedValue().window else {return -1}
        return (window.isVisible ? 1 : 0)|(window.isMiniaturized ? 2 : 0)|(window.occlusionState.contains(.visible) ? 4 : 0)
    }
}
