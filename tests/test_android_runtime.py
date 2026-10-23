"""Source/architecture safeguards for Android native builds, not device inference."""
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from build_android_runtime import elf_identity,verify_source,build_runtime,verify_bundle,REQUIRED_LIBRARIES


class AndroidRuntimeTests(unittest.TestCase):
    def test_runtime_source_requires_reviewed_commit_and_clean_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):return subprocess.check_output(['git','-C',directory,*args],text=True).strip()
            git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid')
            source=Path(directory)/'source';source.write_text('fixture source')
            git('add','.');git('commit','-qm','fixture');commit=git('rev-parse','HEAD')
            self.assertEqual(verify_source(directory,commit),Path(directory).resolve())
            with self.assertRaisesRegex(ValueError,'reviewed commit'):verify_source(directory)
            source.write_text('changed')
            with self.assertRaisesRegex(ValueError,'clean'):verify_source(directory,commit)
            source.write_text('fixture source');(Path(directory)/'untracked.c').write_text('unreviewed')
            with self.assertRaisesRegex(ValueError,'clean'):verify_source(directory,commit)

    def test_host_or_non_shared_elf_cannot_be_reported_as_android_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'library.so'
            for architecture,kind in [(62,3),(183,2)]:
                header=bytearray(64);header[:6]=b'\x7fELF\x02\x01'
                struct.pack_into('<HH',header,16,kind,architecture);path.write_bytes(header)
                with self.assertRaises(ValueError):elf_identity(path)

    def test_fabricated_header_without_loadable_segments_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'library.so';header=bytearray(64)
            header[:6]=b'\x7fELF\x02\x01';struct.pack_into('<HH',header,16,3,183)
            path.write_bytes(header)
            with self.assertRaises(ValueError):elf_identity(path)

    def test_contaminated_output_cache_is_refused_without_removing_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'source';source.mkdir()
            output=root/'output';(output/'cmake').mkdir(parents=True)
            cache=output/'cmake/CMakeCache.txt';cache.write_text('GGML_VULKAN:BOOL=ON\n')
            with self.assertRaisesRegex(ValueError,'empty'):
                build_runtime(source,root/'no-ndk',root/'no-cmake',root/'no-ninja',output)
            self.assertEqual(cache.read_text(),'GGML_VULKAN:BOOL=ON\n')

    @unittest.skipUnless(os.environ.get('GENESIS_ANDROID_RUNTIME_OUTPUT'),'Actual cross-compiled runtime bundle required')
    def test_actual_cross_compiled_libraries_match_build_report(self):
        import json
        output=Path(os.environ['GENESIS_ANDROID_RUNTIME_OUTPUT'])
        report=json.loads((output/'runtime-build.json').read_text())
        self.assertFalse(report['publicationAuthorized']);self.assertFalse(report['localInferenceVerified'])
        self.assertEqual(report['deviceAcceptance'],'unrun')
        self.assertEqual({record['path'] for record in report['files']},REQUIRED_LIBRARIES)
        self.assertEqual(verify_bundle(output),report['files'])
        for record in report['files']:
            self.assertEqual(elf_identity(output/'arm64-v8a'/record['path']),record)

    @unittest.skipUnless(os.environ.get('GENESIS_ANDROID_RUNTIME_OUTPUT'),'Actual cross-compiled runtime bundle required')
    def test_actual_bundle_missing_library_notice_or_changed_dependency_is_rejected(self):
        import shutil
        source=Path(os.environ['GENESIS_ANDROID_RUNTIME_OUTPUT'])
        for corruption in ('library','notice','dependency'):
            with self.subTest(corruption=corruption),tempfile.TemporaryDirectory() as directory:
                output=Path(directory);shutil.copytree(source/'arm64-v8a',output/'arm64-v8a')
                shutil.copytree(source/'licenses',output/'licenses')
                if corruption=='library':(output/'arm64-v8a/libggml.so').unlink()
                elif corruption=='notice':(output/'licenses/llama.cpp-LICENSE.txt').unlink()
                else:
                    path=output/'arm64-v8a/libllama.so';data=path.read_bytes()
                    self.assertIn(b'libm.so\0',data)
                    path.write_bytes(data.replace(b'libm.so\0',b'evil.so\0'))
                with self.assertRaises(ValueError):verify_bundle(output)
