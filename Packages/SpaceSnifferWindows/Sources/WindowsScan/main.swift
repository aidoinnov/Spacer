import Foundation
import WindowsScanCore
import SpaceSnifferScanEngine
let args = CommandLine.arguments
func emit<Value: Encodable>(_ value: Value) {
    guard let bytes = try? JSONEncoder().encode(value) else { return }
    FileHandle.standardOutput.write(bytes); FileHandle.standardOutput.write(Data([10]))
}
guard args.count >= 5, args[1] == "--scan", args[3] == "--output" else {
    FileHandle.standardError.write(Data("Usage: WindowsScan --scan ROOT --output NEW.json [--workers N]\n".utf8)); exit(64)
}
let root = args[2], output = args[4], control = ScanControl()
let workers = args.count >= 7 && args[5] == "--workers" ? Int(args[6]) ?? 4 : 4
let input = Thread { while let line = readLine() { if line == "cancel" { control.cancel(); break } } }
input.start()
let result = WindowsScanner.scan(root: root, control: control, workers: workers, progress: { emit($0) })
do {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(result).write(to: URL(fileURLWithPath: output), options: [.atomic])
    emit(["type": "complete", "output": output, "cancelled": result.cancelled ? "true" : "false"])
    exit(0)
} catch {
    emit(["type": "failure", "message": error.localizedDescription]); exit(1)
}
