import copy
import unittest
from merge import merge

class MergeTests(unittest.TestCase):
 def fixture(self,pairs=2):
  return {'pairs':pairs,'started':1,'status':'measured','cleanup':{'removed':True},'scope':'fixed',
          'fixture_storage':'written','fixture_setup_sync':True,'planned_scenarios':['case'],
          'variants':{'before':{'sha256':'a','mode':'parallel2'},'serial':{'sha256':'b','mode':'automatic'}},
          'summary':{'case':{'expected':{'files':1,'allocated_bytes':4096}}},
          'rows':[{'scenario':'case','variant':v,'pair':i,'status':'ok'} for i in range(pairs) for v in ['before','serial']]}
 def test_preserves_every_attempt_and_offsets_pairs(self):
  a=self.fixture();b=self.fixture(3);b['rows'][0]['status']='failed'
  merged=merge(a,b)
  self.assertEqual(merged['pairs'],5);self.assertEqual(len(merged['rows']),10)
  self.assertEqual(merged['rows'][4]['status'],'failed');self.assertEqual(merged['rows'][4]['pair'],2)
  self.assertEqual(merged['rows'][4]['source_pair'],0)
  self.assertNotIn('source_pair',b['rows'][0])
 def test_rejects_changed_binary_or_mode(self):
  for key in ['sha256','mode']:
   b=self.fixture();b['variants']['before'][key]='different'
   with self.assertRaises(ValueError):merge(self.fixture(),b)
 def test_rejects_warmup_pooling_without_losing_audit_rows(self):
  for first_warm in [False,True]:
   a=self.fixture();b=self.fixture();b.update(warmup_pairs=3,warmup_rows=[{'phase':'warmup'}])
   if first_warm:a.update(warmup_pairs=3,warmup_rows=[{'phase':'warmup'}])
   with self.assertRaisesRegex(ValueError,'warmup'):merge(a,b)
 def test_rejects_storage_change(self):
  b=self.fixture();b['fixture_storage']='cloned'
  with self.assertRaises(ValueError):merge(self.fixture(),b)
 def test_rejects_oracle_change(self):
  b=self.fixture();b['summary']['case']['expected']['allocated_bytes']=0
  with self.assertRaises(ValueError):merge(self.fixture(),b)
 def test_rejects_duplicate_or_missing_attempt(self):
  for duplicate in [True,False]:
   b=self.fixture()
   if duplicate:b['rows'][1]=copy.deepcopy(b['rows'][0])
   else:b['rows'].pop()
   with self.assertRaises(ValueError):merge(self.fixture(),b)
 def test_rejects_pair_outside_declared_range(self):
  b=self.fixture();b['rows'][0]['pair']=30
  with self.assertRaises(ValueError):merge(self.fixture(),b)
 def test_rejects_incomplete_cleanup(self):
  b=self.fixture();b['cleanup']['removed']=False
  with self.assertRaises(ValueError):merge(self.fixture(),b)

if __name__=='__main__':unittest.main()
