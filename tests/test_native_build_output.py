"""Build diagnostics must preserve Unicode even with Windows legacy stdout."""
import os
from pathlib import Path
import subprocess
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]

class NativeBuildOutputTests(unittest.TestCase):
    def test_unicode_godot_output_survives_legacy_console_encoding(self):
        script='''import sys
sys.path.insert(0,'scripts')
import build_native
from types import SimpleNamespace
from unittest.mock import patch
with patch.object(build_native.subprocess,'run',return_value=SimpleNamespace(returncode=0,stdout='GENESIS_MARKER: ورکشاپ 🐾 \\ufffd\\n',stderr='')):
 build_native.run_game('unused-test-executable',[],marker='GENESIS_MARKER')
'''
        environment=os.environ.copy();environment['PYTHONIOENCODING']='cp1252'
        result=subprocess.run([sys.executable,'-c',script],cwd=ROOT,env=environment,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr.decode('utf-8',errors='replace'))
        self.assertIn('ورکشاپ 🐾 \ufffd',result.stdout.decode('utf-8'))

if __name__=='__main__':unittest.main()
