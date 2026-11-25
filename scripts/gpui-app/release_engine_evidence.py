"""Validate explicit provenance when a release rebuilds the retained 184B model."""
import hashlib
import json
from pathlib import Path

BASELINE_MODEL_SOURCES = {
    'Model.swift': '89398c980efbfeb3ecd0faa776a74ff79d3ba39177af70f22b9a3d980ecb815b',
    'NodePathStorage.swift': '8d457dfd336fe6c2199face3255771ab1165c8699bab32d94c4048d98f2a2dea',
}


def verify_rebuilt_engine(evidence: Path, version: str, mac_sha: str, windows_sha: str):
    value = json.loads(evidence.read_text())
    assert value['version'] == version
    assert value['engineNodeBytes'] == 184 and value['candidate168Included'] is False
    assert value['modelSources'] == BASELINE_MODEL_SOURCES, 'Release model differs from retained 184B sources'
    assert value['backendSHA256'] == {'mac': mac_sha, 'windows': windows_sha}, 'Backend bytes differ from tested payload'
    for host in ('mac', 'windows'):
        log = value['layoutLogs'][host]
        path = (evidence.parent / log['file']).resolve()
        assert path.parent == evidence.parent.resolve(), 'Layout logs must be adjacent evidence files'
        raw = path.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == log['sha256'], 'Layout proof was modified'
        text = raw.decode('utf-8')
        assert 'NODE_STORAGE_STRIDE 184' in text and '0 failures' in text, '184B runtime layout proof missing'
        assert 'error:' not in text and 'NODE_STORAGE_STRIDE 168' not in text
    return value
