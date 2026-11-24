import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

MODULE = Path(__file__).with_name('space_sniffer_mcp.py')
spec = importlib.util.spec_from_file_location('sniffer_mcp', MODULE)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class MCPTests(unittest.TestCase):
    def legacy(self):
        bridge = m.Bridge(directory='/does-not-exist')
        bridge.handle({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'test','version':'1'}}})
        return bridge
    def test_legacy_catalog_and_no_app(self):
        b = self.legacy()
        catalog = b.handle({'jsonrpc':'2.0','id':2,'method':'tools/list'})
        self.assertGreaterEqual(len(catalog['tools']), 18)
        result = b.handle({'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'app_status','arguments':{}}})
        self.assertTrue(result['isError'])
        self.assertNotIn('trash', {t['name'] for t in catalog['tools']})
    def test_modern_stateless_discovery(self):
        b = m.Bridge()
        meta = {'io.modelcontextprotocol/protocolVersion':m.MODERN,'io.modelcontextprotocol/clientCapabilities':{}}
        result = b.handle({'jsonrpc':'2.0','id':'d','method':'server/discover','params':{'_meta':meta}})
        self.assertEqual(result['resultType'],'complete'); self.assertIn(m.MODERN,result['supportedVersions'])
        result = b.handle({'jsonrpc':'2.0','id':2,'method':'tools/list','params':{'_meta':meta}})
        self.assertIn('ttlMs',result)
        with self.assertRaises(m.RPCError): b.handle({'jsonrpc':'2.0','id':3,'method':'tools/list','params':{'_meta':{'io.modelcontextprotocol/protocolVersion':'9999'}}})
    def test_input_validation(self):
        b = self.legacy()
        for args in [{'limit':501},{'limit':True},{'offset':-1},{'arbitrary_shell':'rm'}]:
            with self.assertRaises(m.RPCError): b.handle({'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'tree_children','arguments':args}})
    def test_notifications_produce_no_response(self):
        b = self.legacy(); self.assertIsNone(b.handle({'jsonrpc':'2.0','method':'notifications/initialized'}))
    def test_ping_can_precede_initialization_but_tools_cannot(self):
        b=m.Bridge(directory='/does-not-exist')
        self.assertEqual(b.handle({'jsonrpc':'2.0','id':1,'method':'ping'}),{})
        with self.assertRaises(m.RPCError):b.handle({'jsonrpc':'2.0','id':2,'method':'tools/list'})
    def test_stdio_oversized_line_and_bad_names_do_not_break_next_request(self):
        messages=[json.dumps({'jsonrpc':'2.0','id':'init','method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'test','version':'1'}}}),
                  'x'*1048577,
                  json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':[]}}),
                  json.dumps({'jsonrpc':'2.0','id':3,'method':'resources/read','params':{'uri':{}}}),
                  json.dumps({'jsonrpc':'2.0','id':4,'method':'ping','params':False}),
                  json.dumps({'jsonrpc':'2.0','id':5,'method':'ping'})]
        proc=subprocess.run([sys.executable,str(MODULE)],input='\n'.join(messages)+'\n',text=True,capture_output=True,check=True,timeout=15)
        rows=[json.loads(line) for line in proc.stdout.splitlines()]
        self.assertEqual(len(rows),6)
        self.assertEqual([r['error']['code'] for r in rows[1:5]],[-32600,-32602,-32602,-32602])
        self.assertEqual(rows[-1],{'jsonrpc':'2.0','id':5,'result':{}})
        self.assertEqual(proc.stderr,'')
    def test_stdio_is_utf8_even_with_an_ascii_console(self):
        messages=[{'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'test','version':'1'}}},
                  {'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'tree_children','arguments':{'한국어':'값'}}}]
        proc=subprocess.run([sys.executable,str(MODULE)],input=('\n'.join(json.dumps(x) for x in messages)+'\n').encode(),capture_output=True,
                            env={**os.environ,'PYTHONIOENCODING':'ascii'},check=True,timeout=15)
        rows=[json.loads(line.decode('utf-8')) for line in proc.stdout.splitlines()]
        self.assertEqual(rows[1]['error']['code'],-32602)
        self.assertIn('한국어',rows[1]['error']['message'])
        self.assertNotIn(b'\r\n',proc.stdout)
        self.assertEqual(proc.stderr,b'')
    def test_nonobject_params_are_invalid_even_when_falsey(self):
        b = self.legacy()
        for value in [None,False,0,[], '']:
            with self.subTest(value=value):
                with self.assertRaises(m.RPCError) as error:
                    b.handle({'jsonrpc':'2.0','id':3,'method':'ping','params':value})
                self.assertEqual(error.exception.code,-32602)
    def test_nonstring_tool_and_resource_names_are_invalid_params(self):
        b = self.legacy()
        for method,key in [('tools/call','name'),('resources/read','uri')]:
            for value in [None,[],{},False,3]:
                with self.subTest(method=method,value=value):
                    with self.assertRaises(m.RPCError) as error:
                        b.handle({'jsonrpc':'2.0','id':4,'method':method,'params':{key:value}})
                    self.assertEqual(error.exception.code,-32602)
    def test_subtree_cursor_schema_is_additive_and_bounded(self):
        query = m.TOOL_MAP['query_nodes']
        schema = query['inputSchema']
        m.validate({'traversal':'subtree','cursor':'a'*36,'cancel_cursor':True,'budget':1}, schema)
        m.validate({'offset':123,'budget':100000}, schema)
        self.assertFalse(query['annotations']['idempotentHint'])
        for args in [{'traversal':'arbitrary'}, {'cursor':'a'*37}, {'cancel_cursor':'yes'}]:
            with self.assertRaises(m.RPCError): m.validate(args,schema)
    def test_stdio_is_only_json_lines_and_preserves_ids(self):
        messages = ['{broken',json.dumps({'jsonrpc':'2.0','id':'init','method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'test','version':'1'}}}),
                    json.dumps({'jsonrpc':'2.0','method':'notifications/initialized'}),json.dumps({'jsonrpc':'2.0','id':99,'method':'tools/list'})]
        r = subprocess.run([sys.executable,str(MODULE)],input='\n'.join(messages)+'\n',text=True,capture_output=True,check=True)
        rows = [json.loads(line) for line in r.stdout.splitlines()]
        self.assertEqual(len(rows),3);self.assertEqual(rows[0]['error']['code'],-32700);self.assertEqual(rows[1]['id'],'init');self.assertEqual(rows[2]['id'],99)
    def test_explicit_configuration_and_legacy_snapshot_options(self):
        m.validate({'configuration_path':'/fixture/config.xml','inspect_only':True}, m.TOOL_MAP['report_export']['inputSchema'])
        m.validate({'output':'/fixture/new.txt','configuration_path':'/fixture/config.xml','configuration_index':0,'max_output_bytes':512}, m.TOOL_MAP['report_export']['inputSchema'])
        m.validate({'path':'/fixture/old.sns','legacy_code_page':949,'root_index':1,'inspect_only':True}, m.TOOL_MAP['snapshot_load']['inputSchema'])
        for name, args in [('report_export', {'max_output_bytes':0}), ('report_export', {'configuration_index':True}),
                           ('snapshot_load', {'path':'/x','legacy_code_page':0}), ('snapshot_load', {'path':'/x','root_index':-1})]:
            with self.assertRaises(m.RPCError): m.validate(args,m.TOOL_MAP[name]['inputSchema'])
    def test_insecure_descriptor_directory_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory).chmod(0o755)
            self.assertEqual(m.Bridge(directory=directory).instances(),[])

if __name__ == '__main__': unittest.main()
