import Foundation
@main enum FilterBenchmark {
 static func main() throws {
  let folders = 100, perFolder = 2500
  let scenario = CommandLine.arguments.dropFirst().first ?? "name"
  var snapshot = ScanSnapshot(rootPath: "/bench")
  snapshot.nodes.append(DiskNode(id:0,parent:nil,path:"/bench",name:"bench",isDirectory:true))
  for folder in 0..<folders {
   var parent = 0
   for name in ["folder-\(folder)", "inner", "cache"] {
    let id = snapshot.nodes.count
    let path = snapshot.nodes[parent].path + "/" + name
    snapshot.nodes[parent].children.append(id)
    var node = DiskNode(id:id,parent:parent,path:path,name:name,isDirectory:true)
    node.nativeAttributes = name == "folder-\(folder)" && folder % 10 == 0 ? 0x12 : 0x10
    snapshot.nodes.append(node);parent = id
   }
   for file in 0..<perFolder {
    let id = snapshot.nodes.count
    let name = "FILE-\(file)." + (file % 2 == 0 ? "BIN" : "txt")
    snapshot.nodes[parent].children.append(id)
    snapshot.nodes.append(DiskNode(id:id,parent:parent,path:snapshot.nodes[parent].path+"/"+name,name:name,logicalBytes:1,allocatedBytes:4096))
   }
  }
  snapshot.tags[snapshot.rootPath] = 1
  let text = scenario == "folder" ? "\\inner;*.bin" : scenario == "tagsHidden" ? ":red;*.bin" : "*.bin;logicalsize>0b"
  let filter = try ScanFilter(text)
  let start = Date()
  let weights = filter.weights(in:snapshot,mode:.logical,showHidden:scenario != "tagsHidden")
  let expected: Int64 = scenario == "tagsHidden" ? 112500 : 125000
  precondition(weights[0] == expected)
  print(String(decoding:try JSONSerialization.data(withJSONObject:["scenario":scenario,"files":250000,"seconds":Date().timeIntervalSince(start),"checksum":weights[0]],options:.sortedKeys),as:UTF8.self))
 }
}
