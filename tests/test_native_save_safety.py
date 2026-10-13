"""Godot4.7.2 save/crash proof. Isolated copies/user directories; no personal saves."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from build_save_adapter import build_adapter

ROOT=Path(__file__).resolve().parents[1]

class NativeSaveSafetyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine=os.environ.get('GENESIS_TEST_GODOT') or shutil.which('godot')
        if not cls.engine:raise unittest.SkipTest('Godot4.7.2 required for native save tests')
        version=subprocess.check_output([cls.engine,'--version'],text=True).strip()
        if not version.startswith('4.7.2.stable.'):raise unittest.SkipTest('Required Godot4.7.2 unavailable; installed '+version)
        cls.workspace=tempfile.TemporaryDirectory(prefix='genesis-save-tests-')
        cls.base=Path(cls.workspace.name);cls.project=cls.base/'native'
        shutil.copytree(ROOT/'native',cls.project,ignore=shutil.ignore_patterns('.godot'))
        build_adapter(cls.project)
        cls.evidence=Path(os.environ['GENESIS_SAVE_EVIDENCE_DIR']) if os.environ.get('GENESIS_SAVE_EVIDENCE_DIR') else None
        if cls.evidence:cls.evidence.mkdir(parents=True,exist_ok=True)
        cls.run_engine('import',['--editor','--import','--quit'],cls.base/'import-data')

    @classmethod
    def tearDownClass(cls):cls.workspace.cleanup()

    @classmethod
    def environment(cls,data):
        env=os.environ.copy();env['XDG_DATA_HOME']=str(data)
        if os.name=='nt':env['APPDATA']=str(data)
        return env

    @classmethod
    def run_engine(cls,name,args,data):
        result=subprocess.run([cls.engine,'--headless','--path',str(cls.project),*args],env=cls.environment(data),capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=60)
        text=result.stdout+result.stderr
        if cls.evidence:(cls.evidence/(name+'.log')).write_text(text)
        if result.returncode or 'SCRIPT ERROR' in text:raise AssertionError(name+' failed:\n'+text)
        return text

    def test_real_state_regression_suite(self):
        text=self.run_engine('native-state',['--script','res://tests/state_test.gd'],self.base/'state-data')
        self.assertIn('GENESIS_STATE_TEST_OK',text);self.assertIn('0 failed',text)

    def test_native_adapter_abi_and_missing_library(self):
        text=self.run_engine('adapter-abi',['--script','res://tests/save_adapter_test.gd'],self.base/'adapter-data')
        self.assertIn('GENESIS_SAVE_ADAPTER_OK',text)
        project=self.base/'missing-native'
        shutil.copytree(self.project,project,ignore=shutil.ignore_patterns('.godot','genesis_save.so','genesis_save.dll'))
        environment=self.environment(self.base/'missing-data')
        for name,args in [('missing-import',['--editor','--import','--quit']),('missing-adapter',['--script','res://tests/save_adapter_test.gd','--','--expect-missing'])]:
            result=subprocess.run([self.engine,'--headless','--path',str(project),*args],env=environment,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=60)
            output=result.stdout+result.stderr
            if self.evidence:(self.evidence/(name+'.log')).write_text(output)
            self.assertEqual(result.returncode,0,output);self.assertNotIn('SCRIPT ERROR',output)
            if name=='missing-adapter':self.assertIn('GENESIS_MISSING_ADAPTER_OK',output)

    def interrupted_writes(self,kind):
        for phase in ['after_stage','after_backup','before_replace','after_delete','after_commit']:
            with self.subTest(kind=kind,phase=phase):
                data=self.base/(kind+'-'+phase);args=['--script','res://tests/save_crash_fixture.gd','--','--phase='+phase]
                if kind=='index':args.append('--index')
                process=subprocess.Popen([self.engine,'--headless','--path',str(self.project),*args],env=self.environment(data),stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding="utf-8",errors="replace")
                marker=data/'EvidenceGenesis/boundary.json'
                reached=False
                try:
                    deadline=time.monotonic()+15
                    while not marker.exists() and process.poll() is None and time.monotonic()<deadline:time.sleep(.02)
                    reached=marker.exists()
                    if reached:self.assertEqual(json.loads(marker.read_text())['phase'],phase)
                finally:
                    if process.poll() is None:process.kill()
                    stdout,stderr=process.communicate(timeout=10)
                    if process.stdout:process.stdout.close()
                    if process.stderr:process.stderr.close()
                actual=list(data.rglob('*')) if data.exists() else []
                self.assertTrue(reached,'Requested boundary not reached: '+phase+'; files='+str(actual)+'; child='+stdout+stderr)
                if self.evidence:(self.evidence/(kind+'-'+phase+'-killed.log')).write_text(stdout+stderr)
                saved=data/'EvidenceGenesis/crash.json'
                candidate=saved if saved.exists() else Path(str(saved)+'.backup')
                self.assertTrue(candidate.exists(),'No committed save or recovery backup')
                payload=json.loads(candidate.read_text());self.assertIsInstance(payload,dict)
                read_args=['--script','res://tests/save_crash_fixture.gd','--','--read']+(['--index'] if kind=='index' else [])
                text=self.run_engine(kind+'-'+phase+'-read',read_args,data)
                read=json.loads(next(line.removeprefix('CRASH_READ:') for line in text.splitlines() if line.startswith('CRASH_READ:')))
                self.assertTrue(read['ok'])
                self.assertEqual(read['value'],('After' if phase=='after_commit' else 'Before') if kind=='index' else (2 if phase=='after_commit' else 1))
                if kind=='state':self.assertTrue(read['dedupe'],'Recovery awarded duplicate credit')

    def test_interrupted_workshop_writes(self):self.interrupted_writes('state')
    def test_interrupted_profile_index_writes(self):self.interrupted_writes('index')

if __name__=='__main__':unittest.main()
