"""Cross-compile proof only. This does not claim device execution or Android acceptance."""
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get('GENESIS_ANDROID_NDK'),'Explicit reviewed Android NDK required')
class AndroidAdapterTests(unittest.TestCase):
    def test_arm64_adapter_contains_persistence_and_transaction_entrypoints(self):
        with tempfile.TemporaryDirectory() as directory:
            project=Path(directory)/'native'
            shutil.copytree(ROOT/'native/durability',project/'durability')
            command=[sys.executable,str(ROOT/'scripts/build_save_adapter.py'),'--project',str(project),
                     '--android-ndk',os.environ['GENESIS_ANDROID_NDK']]
            result=subprocess.run(command,text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            output=project/'genesis_save.android.arm64.so'
            data=output.read_bytes()
            self.assertEqual(data[:6],b'\x7fELF\x02\x01')
            self.assertEqual(struct.unpack_from('<H',data,18)[0],183,'Must be AArch64, not host x64')
            for symbol in (b'genesis_save_init',b'genesis_sync_file',b'genesis_replace_file',
                           b'genesis_lock_file',b'genesis_unlock_file'):
                self.assertIn(symbol,data)

    def test_mismatched_ndk_version_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            ndk=Path(directory);(ndk/'source.properties').write_text('Pkg.Revision = 1.0.0\n')
            result=subprocess.run([sys.executable,str(ROOT/'scripts/build_save_adapter.py'),
                                   '--android-ndk',str(ndk)],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('28.2.13676358',result.stderr)
