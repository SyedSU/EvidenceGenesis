"""Real native bridge contract; optional pinned model and Android bundle proofs."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]

class InferenceBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library=os.environ.get('GENESIS_AI_LIBRARY')
        if not cls.library:
            raise unittest.SkipTest('GENESIS_AI_LIBRARY host build required')
        assert Path(cls.library).is_file(), 'Native inference bridge library has not been implemented/built'
        cls.lib=ctypes.CDLL(cls.library)
        cls.lib.genesis_ai_request.argtypes=[ctypes.c_char_p]*4
        cls.lib.genesis_ai_request.restype=ctypes.c_char_p

    def call(self,operation,a='',b='',c=''):
        return json.loads(self.lib.genesis_ai_request(*[x.encode('utf-8') for x in (operation,a,b,c)]).decode('utf-8'))

    def tearDown(self):self.call('shutdown')

    def wait(self,states,timeout=120):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            result=self.call('poll')
            if result['state'] in states:return result
            time.sleep(.01)
        self.fail('Native worker did not finish: '+str(result))

    def test_unloaded_generate_fails_and_unknown_operation_is_rejected(self):
        self.assertEqual(self.call('generate','system','hello','1')['state'],'error')
        self.assertEqual(self.call('unknown')['state'],'error')

    def test_model_requires_absolute_path_and_pinned_hash(self):
        self.assertEqual(self.call('load','relative.gguf')['state'],'error')
        with tempfile.TemporaryDirectory() as directory:
            model=Path(directory)/'fake.gguf';model.write_bytes(b'not reviewed weights')
            self.assertEqual(self.call('load',str(model))['state'],'loading')
            result=self.wait({'error'})
            self.assertIn('hash',result['error'])
            self.assertEqual(self.call('generate','x','y','2')['state'],'error')

    def test_cancel_load_is_observable_and_shutdown_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            model=Path(directory)/'fake.gguf'
            with model.open('wb') as file:file.truncate(512*1024*1024)
            self.call('load',str(model))
            self.assertEqual(self.call('cancel')['state'],'canceling')
            result=self.wait({'canceled'})
            self.assertEqual(result['content'],'')
            self.assertEqual(self.call('shutdown')['state'],'idle')
            self.assertEqual(self.call('shutdown')['state'],'idle')

    def test_oversized_and_invalid_utf8_inputs_are_rejected(self):
        self.assertEqual(self.call('generate','x','a'*40001,'1')['state'],'error')
        raw=self.lib.genesis_ai_request(b'generate',b'\xff',b'x',b'1')
        self.assertEqual(json.loads(raw)['state'],'error')

    @unittest.skipUnless(os.environ.get('GENESIS_AI_MODEL'),'Actual pinned GGUF required')
    def test_real_model_generation_cancellation_and_reuse(self):
        model=Path(os.environ['GENESIS_AI_MODEL']).resolve()
        self.assertEqual(hashlib.sha256(model.read_bytes()).hexdigest(),'74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db')
        self.assertEqual(self.call('load',str(model))['state'],'loading')
        self.assertEqual(self.wait({'ready','error'})['state'],'ready')
        self.assertEqual(self.call('generate','Reply briefly and accurately.','What is two plus two?','proof')['state'],'generating')
        self.assertEqual(self.call('generate','x','y','overlap')['state'],'error')
        result=self.wait({'completed','error'})
        self.assertEqual(result['state'],'completed',result)
        self.assertEqual(result['request_id'],'proof')
        self.assertTrue(result['content'].strip())
        self.assertEqual(self.call('poll')['state'],'ready')
        self.assertEqual(self.call('generate','Write a long story.','A forest adventure.','cancel-proof')['state'],'generating')
        self.call('cancel');result=self.wait({'canceled','error'})
        self.assertEqual(result['state'],'canceled',result);self.assertEqual(result['content'],'')
        self.assertEqual(self.call('generate','Reply briefly.','Say hello.','reuse')['state'],'generating')
        self.assertEqual(self.wait({'completed','error'})['state'],'completed')

if __name__=='__main__':unittest.main()
