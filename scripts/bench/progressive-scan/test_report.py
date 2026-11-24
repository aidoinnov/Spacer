#!/usr/bin/env python3
"""Regression checks for the measurement oracle and report semantics."""
import importlib.util
import json
import os
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace
from pathlib import Path

spec=importlib.util.spec_from_file_location('progressive_run', Path(__file__).with_name('run.py'))
runner=importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
spec2=importlib.util.spec_from_file_location('progressive_analyze',Path(__file__).with_name('analyze.py'))
analyzer=importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(analyzer)


class ReportTests(unittest.TestCase):
    def test_nearest_rank_percentile_and_reproducible_ci(self):
        self.assertEqual(runner.percentile(list(range(1,21)),.95),19)
        self.assertIsNone(runner.percentile([],.95))
        self.assertEqual(runner.ci([25]*20),[25,25])
        self.assertEqual(runner.ci([1,2,3]),runner.ci([1,2,3]))

    def test_no_data_is_not_reported_as_an_instant_useful_result(self):
        truth=dict(files=2,folders=3,allocated_bytes=100,logical_bytes=100,
                   digest='expected',groups={'big':90,'small':10})
        row=dict(files=2,folders=3,allocated_bytes=100,logical_bytes=100,digest='expected',
                 issue_count=0,cancelled=False,publications=[])
        runner.evaluate(row,truth)
        self.assertTrue(row['accurate'])
        self.assertIsNone(row['useful_callback_proxy_ms'])
        self.assertEqual(row['quality_at']['2']['coverage'],0)

    def test_missing_groups_count_as_error_and_regressing_quality_delays_proxy(self):
        truth=dict(files=2,folders=3,allocated_bytes=100,logical_bytes=100,
                   digest='expected',groups={'big':90,'small':10})
        row=dict(truth,issue_count=0,cancelled=False,publications=[
            dict(elapsed_ms=100,observed_bytes=90,groups={'big':90}),
            dict(elapsed_ms=200,observed_bytes=100,groups={'big':90,'small':10}),
            dict(elapsed_ms=300,observed_bytes=10,groups={'small':10}),
            dict(elapsed_ms=400,observed_bytes=100,groups={'big':90,'small':10})])
        runner.evaluate(row,truth)
        self.assertEqual(row['quality_samples'][0]['recall'],.5)
        self.assertEqual(row['quality_samples'][0]['byte_error'],.1)
        self.assertEqual(row['useful_callback_proxy_ms'],400)

    def test_failed_runs_remain_in_denominator_and_zero_cannot_be_improvement(self):
        rows=[dict(scenario='S01',mode='posix',pair=0,status='ok',accurate=True,
                   scan_complete_ms=100,peak_rss_mib=10,cpu_seconds=0,useful_callback_proxy_ms=None),
              dict(scenario='S01',mode='stream',pair=0,status='failed',error='timeout')]
        summary=runner.summarize(rows)['S01']
        self.assertEqual(summary['stream']['failures'],1)
        self.assertIsNone(summary['stream']['metrics']['scan_complete_ms']['p50'])
        self.assertIsNone(summary['posix']['metrics']['cpu_seconds']['paired_improvement_pct'])
        self.assertEqual(summary['stream']['gate'],'pending_GUI_and_full_matrix')

    def test_paired_quantile_ci_has_expected_constant_improvement(self):
        self.assertEqual(analyzer.paired_quantile_ci([(100,50)]*20,.5),[50,50])
        self.assertEqual(analyzer.paired_quantile_ci([(100,50)]*20,.95),[50,50])

    def test_faster_median_does_not_hide_a_failed_p95_gate(self):
        rows=[]
        for pair in range(20):
            for mode,value in [('posix',100),('stream',80 if pair<18 else 111)]:
                rows.append(dict(scenario='S05',pair=pair,mode=mode,status='ok',accurate=True,
                                 scan_complete_ms=value,useful_callback_proxy_ms=value,
                                 peak_rss_mib=10,cpu_seconds=1))
        report=dict(status='measured_engine_only',binary_sha256='0'*64,rows=rows,summary=runner.summarize(rows))
        with tempfile.TemporaryDirectory(prefix='sniffer-gate-test-') as temporary:
            path=Path(temporary)/'report.json';path.write_text(json.dumps(report))
            result=analyzer.analyze([path])['S05']
        self.assertEqual(result['engine_total_time_point_gate'],'failed')
        self.assertEqual(result['adoption'],'pending_GUI_cache_lifecycle_and_full_gate_matrix')

    def test_space_reserve_stops_fixture_before_writing_files(self):
        with tempfile.TemporaryDirectory(prefix='sniffer-guard-test-') as temporary:
            path=Path(temporary)/'fixture'
            with mock.patch.object(runner.shutil,'disk_usage',return_value=SimpleNamespace(free=0)):
                with self.assertRaises(OSError):
                    runner.make_fixture(path,'S01',Path(temporary))
            self.assertEqual(list(path.iterdir()),[])

    def test_backing_reserve_is_checked_even_if_virtual_volume_has_room(self):
        with tempfile.TemporaryDirectory(prefix='sniffer-backing-test-') as temporary:
            path=Path(temporary)/'fixture'
            with mock.patch.object(runner.shutil,'disk_usage',side_effect=[SimpleNamespace(free=2*1024**3),SimpleNamespace(free=512*1024**2)]):
                with self.assertRaises(OSError):
                    runner.make_fixture(path,'S01',Path(temporary))
            self.assertEqual(list(path.iterdir()),[])

    def test_oracle_counts_hardlink_aliases_but_skips_symlinks_and_directories_own_bytes(self):
        with tempfile.TemporaryDirectory(prefix='sniffer-report-test-') as temporary:
            root=Path(temporary)
            (root/'folder').mkdir()
            (root/'folder'/'one').write_bytes(b'abc')
            os.link(root/'folder'/'one',root/'alias')
            (root/'cycle').symlink_to('.')
            (root/'broken').symlink_to('missing')
            expected=runner.oracle(root)
            allocation=(root/'alias').stat().st_blocks*512
            self.assertEqual(expected['files'],2)
            self.assertEqual(expected['folders'],2)
            self.assertEqual(expected['logical_bytes'],6)
            self.assertEqual(expected['allocated_bytes'],allocation*2)
            self.assertEqual(expected['groups'],{'folder':allocation})
            self.assertEqual(expected,runner.oracle(root))


if __name__=='__main__': unittest.main()
