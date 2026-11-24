#!/usr/bin/env python3
"""Freeze same-source control and experimental single-pass readers; no product edits.
Compile PhaseProfile only into diagnostic variants, never shipping Core.
"""
import argparse,hashlib,json,shutil
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
repo=Path(__file__).resolve().parents[3]
baseline=repo/'docs/validation/scan-delivery-2026-11-20/candidate-v9/core'
a.output.mkdir(parents=True,exist_ok=False)
telemetry='''import Foundation
final class PhaseProfile: @unchecked Sendable {
 static let shared = PhaseProfile()
 private let lock = NSLock()
 private var totals: [String: UInt64] = [:]
 private var counts: [String: Int] = [:]
 static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
 func add(_ key: String, _ start: UInt64) {
  let elapsed = Self.now() - start
  lock.lock(); totals[key, default: 0] += elapsed; counts[key, default: 0] += 1; lock.unlock()
 }
 var output: [String: Any] {
  lock.lock(); defer { lock.unlock() }
  return ["sum_wall_ms": totals.mapValues { Double($0)/1e6 }, "calls": counts,
          "scope": "nested phase sums; concurrent reader time overlaps; never sum into scan wall time"]
 }
}
'''
def replace(source,old,new):
 assert source.count(old)==1,old[:100]
 return source.replace(old,new)
for variant in ['control','control-phases','single-pass','single-pass-phases']:
 root=a.output/variant;core=root/'core';core.mkdir(parents=True)
 for file in baseline.glob('*.swift'):shutil.copy2(file,core/file.name)
 profile=(baseline.parent/'profile.swift').read_text()
 if variant.startswith('single-pass'):
  path=core/'OrderedDirectoryReader.swift';s=path.read_text()
  marker='''        let names = try POSIXDirectoryReader().names(at: path, control: control, statistics: &statistics, budget: nameBudget, polling: polling, progress: progress)'''
  addition='''        // EXPERIMENT ONLY: bounded bulk first; no names-first namespace cross-check.
        // A failed/over-budget batch publishes nothing and falls back to legacy.
        var calls = 0, records = 0
        if var entries = native.read(path, control: control, polling: polling, observeCall: { count in
            calls += 1; records += max(0, Int(count))
        }) {
            statistics.bulkCalls += calls; statistics.bulkReturnedRecords += records
            entries.sort { $0.name < $1.name }
            if let budget = nameBudget {
                var charge = 0
                for entry in entries {
                    charge += entry.name.utf8.count + 64
                    guard charge <= budget.bytes else { throw DirectoryNameBudgetError.exceeded }
                }
                guard entries.count <= budget.entries else { throw DirectoryNameBudgetError.exceeded }
            }
            return OrderedDirectoryListing(names: entries.map(\\.name), entries: entries)
        }
        statistics.bulkCalls += calls; statistics.bulkReturnedRecords += records
'''
  s=replace(s,marker,addition+marker);path.write_text(s)
 if variant.endswith('phases'):
  (core/'PhaseProfile.swift').write_text(telemetry)
  path=core/'POSIXDirectoryReader.swift';s=path.read_text()
  s=replace(s,'        var attempt = 0','        let phase = PhaseProfile.now(); defer { PhaseProfile.shared.add("names_including_sort", phase) }\n        var attempt = 0')
  s=replace(s,'            return names.sorted()','            let sortPhase = PhaseProfile.now(); defer { PhaseProfile.shared.add("names_sort_nested", sortPhase) }\n            return names.sorted()');path.write_text(s)
  path=core/'NativeDirectoryMetadata.swift';s=path.read_text()
  marker='''        guard !control.isCancelled, maximumEstimatedBytes >= Self.bufferBytes else { return nil }'''
  s=replace(s,marker,'        let phase = PhaseProfile.now(); defer { PhaseProfile.shared.add("native_read", phase) }\n'+marker);path.write_text(s)
  path=core/'OrderedDirectoryReader.swift';s=path.read_text()
  marker='''        if let entries = batch, entries.count >= 4096 {'''
  s=replace(s,marker,'        let matchPhase = PhaseProfile.now(); defer { PhaseProfile.shared.add("names_match", matchPhase) }\n'+marker);path.write_text(s)
  path=core/'Scanner.swift';s=path.read_text()
  marker='''            let node = snapshot.nodes[id]'''
  s=replace(s,marker,'            let phase = PhaseProfile.now(); defer { PhaseProfile.shared.add("directory_nested", phase) }\n'+marker);path.write_text(s)
  marker='''        output["enumeration_io"] ='''
  assert profile.count(marker)==1
  profile=profile.replace(marker,'        output["phases"] = PhaseProfile.shared.output\n'+marker)
 (root/'profile.swift').write_text(profile)
manifest={str(p.relative_to(a.output)):hashlib.sha256(p.read_bytes()).hexdigest() for p in a.output.rglob('*.swift')}
(a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(a.output)
