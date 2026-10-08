import importlib.util
import json
import os
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('genesis_server',Path(__file__).resolve().parents[1]/'runtime/server.py')
server_module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_module)

class MockModel(BaseHTTPRequestHandler):
    last_payload=None
    def do_GET(self):
        self.send_response(200);self.end_headers();self.wfile.write(b'{"data":[{"id":"test-model"}]}')
    def do_POST(self):
        MockModel.last_payload=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.send_response(200);self.end_headers();self.wfile.write(b'{"choices":[{"message":{"content":"# Tested document"}}]}')
    def log_message(self,*args): pass

class RuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model=ThreadingHTTPServer(('127.0.0.1',0),MockModel)
        cls.app=ThreadingHTTPServer(('127.0.0.1',0),server_module.Handler)
        for srv in (cls.model,cls.app): threading.Thread(target=srv.serve_forever,daemon=True).start()
        cls.base=f'http://127.0.0.1:{cls.app.server_address[1]}'
        cls.env=patch.dict(os.environ,{'GENESIS_MODEL_URL':f'http://127.0.0.1:{cls.model.server_address[1]}/v1'},clear=True);cls.env.start()
    @classmethod
    def tearDownClass(cls):
        cls.env.stop()
        for srv in (cls.model,cls.app):srv.shutdown();srv.server_close()
    def test_health_and_generation_transport(self):
        with urlopen(self.base+'/api/health') as r:self.assertTrue(json.load(r)['available'])
        payload={'title':'Plan','notes':'Use only this note','character':{'name':'Milo','role':'Document maker'},'memories':[{'type':'preference','key':'format','value':'numbered'}]}
        req=Request(self.base+'/api/generate',data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
        with urlopen(req) as r:self.assertEqual(json.load(r)['content'],'# Tested document')
        self.assertIn('numbered',MockModel.last_payload['messages'][1]['content'])
        self.assertEqual(MockModel.last_payload['model'],'test-model')
    def test_rejects_cross_origin_and_invalid_input(self):
        req=Request(self.base+'/api/generate',data=b'{}',headers={'Content-Type':'application/json','Origin':'https://example.com'})
        with self.assertRaises(HTTPError) as e:urlopen(req)
        self.assertEqual(e.exception.code,403)
        req=Request(self.base+'/api/generate',data=b'{}',headers={'Content-Type':'application/json'})
        with self.assertRaises(HTTPError) as e:urlopen(req)
        self.assertEqual(e.exception.code,400)
    def test_no_cloud_model_address(self):
        with patch.dict(os.environ,{'GENESIS_MODEL_URL':'https://example.com/v1'}):
            with self.assertRaises(ValueError):server_module.model_base()
    def test_static_server_does_not_expose_runtime(self):
        with self.assertRaises(HTTPError) as e:urlopen(self.base+'/runtime/server.py')
        self.assertEqual(e.exception.code,404)
    def test_unavailable_model_never_falls_back(self):
        with patch.object(server_module,'local_request',side_effect=ConnectionError()):
            payload={'title':'Plan','notes':'Keep this','character':{'name':'Milo','role':'Document maker'},'memories':[]}
            req=Request(self.base+'/api/generate',data=json.dumps(payload).encode(),headers={'Content-Type':'application/json'})
            with self.assertRaises(HTTPError) as e:urlopen(req)
            self.assertEqual(e.exception.code,503)
            self.assertIn('No cloud fallback',json.load(e.exception)['error'])

if __name__=='__main__':unittest.main()
