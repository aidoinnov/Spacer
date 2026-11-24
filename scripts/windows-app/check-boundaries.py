#!/usr/bin/env python3
"""Check platform ports, adapters and composition directions (not runtime proof)."""
from pathlib import Path
root=Path(__file__).resolve().parents[2]
shared=root/'Packages/SpaceSnifferScanEngine/Sources'
for p in shared.rglob('*.swift'):
    text=p.read_text()
    for token in ['import Darwin','import WinSDK','import AppKit','import WindowsDirectoryIO','#if os(']:
        assert token not in text,(p,token)
core=root/'Packages/SpaceSnifferWindows/Sources/WindowsScanCore'
builder=(core/'WindowsTreeBuilder.swift').read_text()
for forbidden in ['WindowsDirectoryReader(', 'sniffer_open(', 'FileManager', 'import WinSDK', '#if os(']:
    assert forbidden not in builder,forbidden
assert 'Reader: DirectoryBatchReader' in builder
assert 'boundedReader: WindowsDirectoryReader' in (core/'WindowsScanner.swift').read_text()
assert 'WindowsPath.nativeSpelling' in (core/'WindowsDirectoryReader.swift').read_text()
assert 'FileIdExtdDirectoryInfo' in (root/'Packages/SpaceSnifferWindows/Sources/WindowsDirectoryIO/WindowsDirectoryIO.c').read_text()
for p in (root/'WindowsApp').glob('*.cs'):
    assert 'DirectoryWorkerPool' not in p.read_text(),p
print('PASS: portable engine has no OS branches; Windows builder receives reader strategies; Win32 stays in adapter; UI uses process boundary')
