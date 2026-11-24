import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec=importlib.util.spec_from_file_location('retry_report',Path(__file__).with_name('report.py'))
report=importlib.util.module_from_spec(spec);spec.loader.exec_module(report)


def sample(pairs):
    rows=[]
    for scenario in ['denied20','normal-10000']:
        for pair in range(pairs):
            for variant in ['before','after']:
                rows.append(dict(scenario=scenario,pair=pair,variant=variant,status='ok',pair_equal=True,
                    scan_complete_ms=1000 if scenario=='denied20' and variant=='before' else 10 if scenario=='denied20' else 100,
                    peak_rss_mib=10,cpu_seconds=.05,
                    enumeration_io=dict(openDirectoryCalls=21 if scenario=='denied20' else 101,
                                        openRetryDecisions=0,requestedRetryDelaySeconds=0)))
    return dict(status='measured',binaries={k:dict(sha256=k) for k in ['before','after']},rows=rows)


class ReportTests(unittest.TestCase):
    def combine(self,*values):
        with tempfile.TemporaryDirectory(prefix='sniffer-retry-report-') as temporary:
            paths=[]
            for index,value in enumerate(values):
                p=Path(temporary)/f'{index}.json';p.write_text(json.dumps(value));paths.append(p)
            return report.combine(paths)

    def test_combines_all_series_without_colliding_pair_numbers(self):
        result=self.combine(sample(20),sample(80))
        self.assertTrue(result['gate_pass'])
        self.assertEqual(result['summary']['normal-10000']['valid_pairs'],100)
        self.assertEqual(result['summary']['denied20']['attempted_runs'],200)

    def test_slow_tail_is_not_hidden_by_a_fast_median(self):
        data=sample(20)
        for row in data['rows']:
            if row['scenario']=='denied20' and row['variant']=='after' and row['pair']>=18:row['scan_complete_ms']=201
        result=self.combine(data)
        self.assertFalse(result['gate_pass'])
        self.assertFalse(result['summary']['denied20']['gates']['denied_p95_le_200ms'])

    def test_failures_are_kept_in_denominator_and_prevent_adoption(self):
        data=sample(20)
        data['rows'][0].update(status='failed',pair_equal=False)
        data['rows'][1]['pair_equal']=False
        result=self.combine(data)
        self.assertFalse(result['gate_pass'])
        self.assertEqual(result['summary']['denied20']['failed_runs'],2)
        self.assertEqual(result['summary']['denied20']['attempted_runs'],40)

    def test_different_binaries_and_incomplete_reports_cannot_be_pooled(self):
        changed=sample(20);changed['binaries']['after']['sha256']='different'
        with self.assertRaises(ValueError):self.combine(sample(20),changed)
        incomplete=sample(20);incomplete['status']='running'
        with self.assertRaises(ValueError):self.combine(incomplete)


if __name__=='__main__':unittest.main()
