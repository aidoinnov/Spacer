"""Exercise the actual CLI: warmups stay auditable and cannot poison measured rows."""
import json,os,subprocess,tempfile,unittest
from pathlib import Path

SCRIPT=Path(__file__).with_name('compare.py')
class WarmupTests(unittest.TestCase):
 def run_probe(self,fail=False):
  with tempfile.TemporaryDirectory(prefix='sniffer-warmup-tool-',dir='/private/tmp') as d:
   root=Path(d); binary=root/'probe'; output=root/'output.json'
   binary.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
root=Path(sys.argv[2]);files=[p for p in root.rglob('*') if p.is_file()]
print(json.dumps(dict(files=len(files),folders=1+sum(p.is_dir() for p in root.rglob('*')),logical_bytes=sum(p.stat().st_size for p in files),allocated_bytes=sum(p.stat().st_blocks*512 for p in files),issue_count=0,cancelled=False,digest=sys.argv[1] if os.environ.get('FAIL_WARMUP') else 'equal',scan_complete_ms=1,cpu_seconds=.001,peak_rss_mib=1)))
''');binary.chmod(0o755)
   env=dict(os.environ,SNIFFER_BENCH_PARENT=str(root))
   if fail:env['FAIL_WARMUP']='1'
   p=subprocess.run(['python3',str(SCRIPT),'--before',str(binary),'--before-mode','parallel2','--candidate',str(binary),'--pairs','1','--warmup-pairs','2','--scenarios','small1000','--output',str(output)],capture_output=True,text=True,env=env)
   return p,json.loads(output.read_text())
 def test_warmups_are_separate_exact_samples(self):
  proc,raw=self.run_probe();self.assertEqual(proc.returncode,0,proc.stderr)
  self.assertEqual(len(raw['rows']),4);self.assertEqual(len(raw['warmup_rows']),8)
  self.assertEqual({r['pair'] for r in raw['rows']},{0})
  self.assertEqual({r['pair'] for r in raw['warmup_rows']},{-2,-1})
  self.assertTrue(all(r['pair_equal'] and r['phase']=='warmup' for r in raw['warmup_rows']))
  self.assertTrue(raw['cleanup']['removed']);self.assertEqual(raw['status'],'measured')
 def test_bad_warmup_aborts_before_measured_rows(self):
  proc,raw=self.run_probe(True);self.assertNotEqual(proc.returncode,0)
  self.assertEqual(raw['rows'],[]);self.assertEqual(len(raw['warmup_rows']),4)
  self.assertFalse(any(r['pair_equal'] for r in raw['warmup_rows']))
  self.assertTrue(raw['cleanup']['removed']);self.assertNotEqual(raw['status'],'measured')
if __name__=='__main__':unittest.main()
