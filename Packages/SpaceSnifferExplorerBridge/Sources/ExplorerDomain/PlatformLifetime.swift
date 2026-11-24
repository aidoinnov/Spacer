import Foundation
import SpaceSnifferScanEngine
public typealias ScanControl=SpaceSnifferScanEngine.ScanControl
#if os(Windows)
// Foundation on Windows has no Objective-C autorelease pool. The shared codec
// retains the same bounded batches; its value-owned temporaries are released normally.
func autoreleasepool<T>(_ body:() throws->T) rethrows->T{try body()}
#endif
