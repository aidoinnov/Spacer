"""Byte verification and NSIS escaping shared by release composition."""
import hashlib

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()

def verify(root,files):
    actual={p.relative_to(root).as_posix():sha(p) for p in root.rglob('*') if p.is_file()}
    assert actual==files,f'Payload does not match manifest: {root}'

def nsis_quote(value):
    return str(value).replace('$','$$').replace('"','$\\"')
