import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from release_engine_evidence import BASELINE_MODEL_SOURCES, verify_rebuilt_engine


class EngineEvidenceTests(unittest.TestCase):
    def test_rebuilt_model_and_exact_payload_proofs_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = b'NODE_STORAGE_STRIDE 184\nExecuted 10 tests, with 0 failures\n'
            (root/'layout.log').write_bytes(raw)
            value = {'version':'0.3.2','engineNodeBytes':184,'candidate168Included':False,
                     'modelSources':BASELINE_MODEL_SOURCES,'backendSHA256':{'mac':'mac-sha','windows':'win-sha'},
                     'layoutLogs':{host:{'file':'layout.log','sha256':hashlib.sha256(raw).hexdigest()}
                                   for host in ('mac','windows')}}
            proof = root/'evidence.json'
            proof.write_text(json.dumps(value))
            verify_rebuilt_engine(proof,'0.3.2','mac-sha','win-sha')
            with self.assertRaises(AssertionError):
                verify_rebuilt_engine(proof,'0.3.2','other-backend','win-sha')
            value['engineNodeBytes'] = 168
            proof.write_text(json.dumps(value))
            with self.assertRaises(AssertionError):
                verify_rebuilt_engine(proof,'0.3.2','mac-sha','win-sha')
            value['engineNodeBytes'] = 184
            proof.write_text(json.dumps(value))
            (root/'layout.log').write_text('NODE_STORAGE_STRIDE 168\n0 failures')
            with self.assertRaises(AssertionError):
                verify_rebuilt_engine(proof,'0.3.2','mac-sha','win-sha')


if __name__ == '__main__':
    unittest.main()
