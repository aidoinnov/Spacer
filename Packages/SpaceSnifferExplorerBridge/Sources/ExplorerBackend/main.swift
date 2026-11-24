import Foundation
import ExplorerDomain

let args=CommandLine.arguments
ParentLifetime.install(args)
if try runSnapshotImport(args) { exit(0) }
if runDocumentService(args){exit(0)}
#if os(Windows)
guard args.count >= 5, args[1] == "--scan", args[3] == "--output" else { exit(64) }
var includeMounted=false
if let index=args.firstIndex(of:"--volumes") {
    guard args.indices.contains(index+1),["selectedVolume","allVolumes"].contains(args[index+1]) else {bridgeEmit(["type":"failure","message":"잘못된 볼륨 범위입니다."]);exit(64)}
    includeMounted=args[index+1] == "allVolumes"
}
let scanner=WindowsScanSession(root:args[2],output:args[4],includeMounted:includeMounted,binaryWire:usesBinaryWire(args))
scanner.scan()
while let line=readLine() {
    if line == "quit" { scanner.cancel(); break }
    if line == "cancel" { scanner.cancel() }
    else if line == "rescan" { scanner.scan() }
    else if ScopedRescanCommand.matches(line) {
        do { scanner.scan(scope:try ScopedRescanCommand.path(line)) }
        catch { bridgeEmit(["type":"failure","message":"잘못된 재검사 경로입니다."]) }
    }
    else { _=scanner.documents.handle(line) }
}
#else
FileHandle.standardError.write(Data("Use MacScanBridge for native macOS scans; ExplorerBackend supports portable SNS/DU documents.\n".utf8))
exit(64)
#endif
