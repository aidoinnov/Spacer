import copy
import unittest
from report import SCENARIOS, VARIANTS, score


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.raw = dict(pairs=20, planned_scenarios=list(SCENARIOS), status='measured',
                        cleanup=dict(removed=True), scope='fixture', variants={}, rows=[], summary={})
        for scenario, (files, folders) in SCENARIOS.items():
            self.raw['summary'][scenario] = dict(expected=dict(allocated_bytes=files*4096))
            for pair in range(20):
                for variant in VARIANTS:
                    self.raw['rows'].append(dict(scenario=scenario, pair=pair, variant=variant,
                        status='ok', exit_status=0, pair_equal=True, files=files, folders=folders,
                        logical_bytes=sum(1+i%100 for i in range(files)), allocated_bytes=files*4096,
                        issue_count=0, cancelled=False, digest='a'*64, scan_complete_ms=10,
                        cpu_seconds=.01, peak_rss_mib=10))

    def testCompleteEqualDataPasses(self):
        self.assertEqual(score(self.raw)['adopted'], ['parallel2', 'parallel4'])
    def testDeclaredProductionVariantsAreCompleteButMissingDeclaredVariantHolds(self):
        raw = copy.deepcopy(self.raw)
        raw['variants'] = {v: {} for v in ['before','serial','parallel2']}
        raw['rows'] = [r for r in raw['rows'] if r['variant']!='parallel4']
        self.assertEqual(score(raw)['adopted'], ['parallel2'])
        raw['variants']['parallel4'] = {}
        self.assertEqual(score(raw)['adopted'], [])

    def with_warmups(self):
        raw = copy.deepcopy(self.raw)
        raw['warmup_pairs'] = 1
        raw['warmup_rows'] = [dict(row, pair=-1, phase='warmup') for row in raw['rows'] if row['pair'] == 0]
        return raw

    def testAuditedWarmupsPassWithoutEnteringTimedPopulation(self):
        raw = self.with_warmups()
        self.assertEqual(score(raw)['adopted'], ['parallel2', 'parallel4'])
        self.assertEqual(score(raw)['pairs'], 20)

    def testMissingDuplicateWrongOracleOrDivergentWarmupHolds(self):
        for mutate in [lambda r: r['warmup_rows'].pop(),
                       lambda r: r['warmup_rows'].__setitem__(1, copy.deepcopy(r['warmup_rows'][0])),
                       lambda r: r['warmup_rows'][0].update(files=0),
                       lambda r: r['warmup_rows'][0].update(digest='b'*64),
                       lambda r: r.update(warmup_pairs=0)]:
            raw = self.with_warmups(); mutate(raw)
            self.assertEqual(score(raw)['adopted'], [])

    def testMissingDuplicateFailedNonfiniteAndWrongOracleHold(self):
        mutations = [lambda r: r['rows'].pop(),
                     lambda r: r['rows'].__setitem__(1, copy.deepcopy(r['rows'][0])),
                     lambda r: r['rows'][3].update(status='failed'),
                     lambda r: r['rows'][3].update(scan_complete_ms=float('nan')),
                     lambda r: r['rows'][3].update(files=99),
                     lambda r: r['rows'][3].update(digest='b'*64),
                     lambda r: r['rows'][3].update(allocated_bytes=0)]
        for mutate in mutations:
            raw = copy.deepcopy(self.raw)
            mutate(raw)
            self.assertNotIn('parallel4', score(raw)['adopted'])

    def testTailRegressionIsNotHiddenByMedian(self):
        for row in self.raw['rows']:
            if row['variant'] == 'parallel4' and row['pair'] >= 18:
                row['scan_complete_ms'] = 100
        self.assertNotIn('parallel4', score(self.raw)['adopted'])

    def testConsistentlyWrongAllocationDoesNotPassCrossVariantEquality(self):
        for row in self.raw['rows']:
            row['allocated_bytes'] = 0
        self.assertEqual(score(self.raw)['adopted'], [])

    def testCpuAndMemoryRegressionsHoldDespiteFastLatency(self):
        for metric, value in [('cpu_seconds', .02), ('peak_rss_mib', 50)]:
            raw = copy.deepcopy(self.raw)
            for row in raw['rows']:
                if row['variant'] == 'parallel4':
                    row.update(scan_complete_ms=1)
                    row[metric] = value
            self.assertNotIn('parallel4', score(raw)['adopted'])

    def testExplorationAndMissingScenarioCannotAuthorizeAdoption(self):
        for mutate in [lambda r: r.update(pairs=5),
                       lambda r: r['planned_scenarios'].pop(),
                       lambda r: r.update(status='running'),
                       lambda r: r['cleanup'].update(removed=False)]:
            raw = copy.deepcopy(self.raw)
            mutate(raw)
            self.assertEqual(score(raw)['adopted'], [])


if __name__ == '__main__':
    unittest.main()
