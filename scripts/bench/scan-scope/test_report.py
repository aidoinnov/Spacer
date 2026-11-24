import copy,unittest
from report import score
class ScopeGateTests(unittest.TestCase):
 def fixture(self):
  raw=dict(pairs=20,binaries={},scope='test',status='measured',control_removed=True,rows=[])
  for scenario in ['mounted','control10000']:
   for pair in range(20):
    for variant in ['before_all','after_all','after_selected']:
     files,folders,logical=(100,5,300) if scenario=='mounted' and variant=='after_selected' else (6100,37,30300) if scenario=='mounted' else (10000,101,505000)
     raw['rows'].append(dict(scenario=scenario,pair=pair,variant=variant,status='ok',same_scope_equal=True,digest='selected' if scenario=='mounted' and variant=='after_selected' else 'same',files=files,folders=folders,logical_bytes=logical,issue_count=0,cancelled=False,scan_complete_ms=100,cpu_seconds=1,peak_rss_mib=10,volume_coverage=dict(traversal='allVolumes' if variant=='after_all' else 'selectedVolume',excludedCount=1 if scenario=='mounted' and variant=='after_selected' else 0)))
  return raw
 def test_complete_and_failure_denominators(self):
  raw=self.fixture();self.assertTrue(score(raw)['passed'])
  for key,value in [('status','failed'),('digest','bad'),('files',0),('cancelled',True),('scan_complete_ms',0),('cpu_seconds',float('nan')),('pair',1)]:
   bad=copy.deepcopy(raw);bad['rows'][0][key]=value;self.assertFalse(score(bad)['passed'],key)
  missing=copy.deepcopy(raw);missing['rows'].pop();self.assertFalse(score(missing)['passed'])
  wrong=copy.deepcopy(raw);wrong['rows'][2]['volume_coverage']['traversal']='allVolumes';self.assertFalse(score(wrong)['passed'])
  dirty=copy.deepcopy(raw);dirty['control_removed']=False;self.assertFalse(score(dirty)['passed'])
if __name__=='__main__':unittest.main()
