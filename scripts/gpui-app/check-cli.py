#!/usr/bin/env python3
"""Functional legacy headless CLI acceptance; does not launch a GUI or time scans."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();assert not args.output.exists()
    args.output.mkdir(parents=True)
    report={'binary':str(args.binary),'sha256':hashlib.sha256(args.binary.read_bytes()).hexdigest(),
            'scope':'Legacy macOS Swift headless CLI; separate from the GPUI executable','checks':[]}
    def run(name,arguments,expected=0,oracle=None):
        p=subprocess.run([str(args.binary),*arguments],capture_output=True,text=True,timeout=90)
        (args.output/(name+'.stdout')).write_text(p.stdout)
        (args.output/(name+'.stderr')).write_text(p.stderr)
        row={'name':name,'exit':p.returncode,'expectedExit':expected,'passed':p.returncode==expected}
        if row['passed'] and oracle:
            try:oracle(p.stdout)
            except Exception as error:row.update(passed=False,error=repr(error))
        report['checks'].append(row)
        print(json.dumps(row),flush=True)
    with tempfile.TemporaryDirectory(prefix='spacer-cli-owned-') as temp:
        root=Path(temp)/'input';root.mkdir();(root/'branch').mkdir()
        for name,size in [('branch/한글.txt',33),('archive.zip',8193),('.hidden.txt',13)]:
            (root/name).write_bytes(b'x'*size)
        scan=['--cli','--scan',str(root)]
        sns=args.output/'scan.sns';txt=args.output/'files.txt'
        def fields(**expected):
            def check(stdout):
                value=json.loads(stdout)
                for key,wanted in expected.items():assert value[key]==wanted,(key,value)
            return check
        def help_text(text):assert '--cli --scan' in text and '--output' in text
        run('help',['--help'],oracle=help_text)
        run('scan',scan,oracle=fields(files=3,folders=2,logicalBytes=8239,issues=0,cancelled=False))
        run('logical-filter',scan+['--filter','*.zip','--logical'],oracle=fields(matchedBytes=8193))
        run('hide-hidden',scan+['--filter','*.txt','--logical','--hide-hidden'],oracle=fields(matchedBytes=33))
        run('save-sns',scan+['--output',str(sns)],oracle=fields(files=3,logicalBytes=8239))
        run('load-sns',['--cli','--load',str(sns)],oracle=fields(files=3,logicalBytes=8239))
        def roots(stdout):
            value=json.loads(stdout)['roots'];assert len(value)==1,value
            assert value[0]['files']==3 and value[0]['logical_bytes']==8239,value
        run('list-roots',['--cli','--load',str(sns),'--list-roots'],oracle=roots)
        run('export-txt',['--cli','--load',str(sns),'--output',str(txt)])
        original=txt.read_bytes()
        assert set(original.decode().splitlines())=={str(root/'branch/한글.txt'),str(root/'archive.zip'),str(root/'.hidden.txt')}
        run('existing-output',['--cli','--load',str(sns),'--output',str(txt)],1)
        assert txt.read_bytes()==original,'Existing output was modified'
        for name,arguments in [
            ('missing-root',['--cli','--scan',str(root/'missing')]),
            ('invalid-filter',scan+['--filter','logicalsize>bad']),
            ('unknown-option',scan+['--bogus']),
            ('missing-filter-value',scan+['--filter']),
            ('flag-as-filter-value',scan+['--filter','--logical']),
            ('conflicting-inputs',scan+['--load',str(sns)]),
            ('duplicate-input',scan+['--scan',str(root)]),
            ('invalid-codepage',['--cli','--load',str(sns),'--legacy-code-page','0']),
            ('load-only-option',scan+['--legacy-code-page','949']),
            ('ignored-list-output',['--cli','--load',str(sns),'--list-roots','--output',str(args.output/'ignored.sns')]),
            ('unsupported-output',scan+['--output',str(args.output/'bad.csv')]),
        ]:run(name,arguments,1)
        config=args.output/'format.xml'
        encoded=base64.b64encode('<%pathfile%>{&br}'.encode('utf-16le')).decode()
        config.write_text(f'<exportConfig version="3"><description>Owned format</description><detailFormat>{encoded}</detailFormat><blockSorting>files</blockSorting><fineSorting>size</fineSorting><fineSortingDirection>desc</fineSortingDirection></exportConfig>')
        run('inspect-config',['--cli','--inspect-config',str(config)],oracle=fields(document_kind='exportConfig'))
        configured=scan+['--export-config',str(config),'--output',str(args.output/'configured.txt')]
        run('configured-export',configured)
        run('configured-existing-output',configured,1)
        run('configured-byte-cap',scan+['--export-config',str(config),'--output',str(args.output/'capped.txt'),'--max-output-bytes','1'],1)
        assert not (args.output/'capped.txt').exists(),'Failed output was published'
        # All three artifact forms must refuse replacement, including an input SNS.
        saved=sns.read_bytes()
        run('existing-sns',scan+['--output',str(sns)],1);assert sns.read_bytes()==saved
        run('input-is-output',['--cli','--load',str(sns),'--output',str(sns)],1);assert sns.read_bytes()==saved
        run('configured-sns-invalid',scan+['--export-config',str(config),'--output',str(args.output/'invalid.sns')],1)
        report['oracle']={'files':3,'folders':2,'logicalBytes':8239}
    report['fixtureRemoved']=not Path(temp).exists()
    report['passed']=all(row['passed'] for row in report['checks'])
    (args.output/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(0 if report['passed'] else 1)


if __name__=='__main__':main()
