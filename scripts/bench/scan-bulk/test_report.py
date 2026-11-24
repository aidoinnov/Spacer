import copy
import unittest
from report import REQUIRED, merge, score

class GateTests(unittest.TestCase):
    def fixture(self):
        raw=dict(scope='test',pairs=20,variants={'posix':{},'ordered':{}},status='measured',cleanup={'exists_after':False},rows=[])
        for scenario in REQUIRED:
            for pair in range(20):
                for variant,elapsed in [('posix',100),('ordered',90)]:
                    raw['rows'].append(dict(scenario=scenario,pair=pair,variant=variant,status='ok',pair_equal=True,digest='same',scan_complete_ms=elapsed,cpu_seconds=1,peak_rss_mib=10,metadata_requests_per_entry=1))
        return raw
    def test_complete_pass_and_adoption_blockers(self):
        raw=self.fixture();self.assertTrue(score(raw)['passed'])
        for field,value in [('status','failed'),('pair_equal',False),('digest','different'),('scan_complete_ms',float('nan'))]:
            broken=copy.deepcopy(raw);broken['rows'][0][field]=value
            self.assertFalse(score(broken)['passed'],field)
        missing=copy.deepcopy(raw);missing['rows'].pop();self.assertFalse(score(missing)['passed'])
        duplicate=copy.deepcopy(raw);duplicate['rows'][0]['pair']=1;self.assertFalse(score(duplicate)['passed'])
        memory=copy.deepcopy(raw)
        for row in memory['rows']:
            if row['variant']=='ordered':row['peak_rss_mib']=43
        self.assertFalse(score(memory)['passed'])
        dirty=copy.deepcopy(raw);dirty['cleanup']['exists_after']=True;self.assertFalse(score(dirty)['passed'])

    def test_fixed_expansion_retains_initial_failures_and_checks_binary_identity(self):
        raw=self.fixture();raw['variants']={'posix':{'sha256':'a'},'ordered':{'sha256':'b'}}
        extra=copy.deepcopy(raw);extra['planned_scenarios']=['small1000'];extra['rows']=[r for r in extra['rows'] if r['scenario']=='small1000']
        combined=merge(raw,extra);self.assertTrue(score(combined)['passed'])
        self.assertEqual(score(combined)['scenarios']['small1000']['variants']['posix']['attempted'],40)
        raw['rows'][0]['status']='failed';self.assertFalse(score(merge(raw,extra))['passed'])
        extra['variants']['ordered']['sha256']='c'
        with self.assertRaises(AssertionError):merge(raw,extra)

if __name__=='__main__':unittest.main()
