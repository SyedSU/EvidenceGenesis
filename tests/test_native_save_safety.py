"""Godot4.7.2 save/crash proof. Isolated copies/user directories; no personal saves."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from build_save_adapter import build_adapter

def windows_dialogs(pid):
    if os.name!='nt':return []
    import ctypes
    from ctypes import wintypes
    user=ctypes.WinDLL('user32',use_last_error=True)
    callback_type=ctypes.WINFUNCTYPE(wintypes.BOOL,wintypes.HWND,wintypes.LPARAM)
    user.GetWindowThreadProcessId.argtypes=[wintypes.HWND,ctypes.POINTER(wintypes.DWORD)]
    user.GetWindowTextW.argtypes=[wintypes.HWND,wintypes.LPWSTR,ctypes.c_int]
    user.EnumWindows.argtypes=[callback_type,wintypes.LPARAM]
    user.EnumChildWindows.argtypes=[wintypes.HWND,callback_type,wintypes.LPARAM]
    found=[]
    def text(window):
        value=ctypes.create_unicode_buffer(1024);user.GetWindowTextW(window,value,len(value));return value.value
    @callback_type
    def child(window,_unused):
        value=text(window)
        if value:found.append(value)
        return True
    @callback_type
    def top(window,_unused):
        owner=wintypes.DWORD();user.GetWindowThreadProcessId(window,ctypes.byref(owner))
        if owner.value==pid:
            found.append(text(window));user.EnumChildWindows(window,child,0)
        return True
    user.EnumWindows(top,0)
    return found

def pause_and_kill(command,environment,marker,log_path,wait_seconds=15):
    reached=False;dialogs=[];boundary=None;killed=False
    # Drain startup output directly to a file; waiting on a marker while PIPEs
    # are unread can block the child before it reaches the tested boundary.
    with log_path.open('wb') as output:
        process=subprocess.Popen(command,env=environment,stdout=output,stderr=subprocess.STDOUT)
        try:
            deadline=time.monotonic()+wait_seconds
            while not marker.exists() and process.poll() is None and time.monotonic()<deadline:time.sleep(.02)
            reached=marker.exists()
            if reached:boundary=read_save_json(marker)
            else:dialogs=windows_dialogs(process.pid)
        finally:
            if process.poll() is None:process.kill();killed=True
            process.wait(timeout=10)
    return {'reached':reached,'boundary':boundary,'pid':process.pid,'killed':killed,'output':log_path.read_text(encoding='utf-8',errors='replace'),'dialogs':dialogs}

def read_save_json(path):
    return json.loads(path.read_text(encoding="utf-8"))

class CrashHarnessTests(unittest.TestCase):
    def test_save_evidence_reads_utf8_with_legacy_default_encoding(self):
        with tempfile.TemporaryDirectory(prefix='genesis-save-encoding-') as temp:
            path=Path(temp)/'save.json';expected={'notes':'ورکشاپ 🐾 ”'}
            path.write_text(json.dumps(expected,ensure_ascii=False),encoding='utf-8')
            original_open=Path.open
            def legacy_open(instance,*args,**kwargs):
                if kwargs.get('encoding') in (None,'locale'):kwargs['encoding']='cp1252'
                return original_open(instance,*args,**kwargs)
            with patch.object(Path,'open',legacy_open):self.assertEqual(read_save_json(path),expected)

    def test_child_startup_output_cannot_block_boundary_detection(self):
        with tempfile.TemporaryDirectory(prefix='genesis-noisy-child-') as temp:
            base=Path(temp);marker=base/'marker.json'
            code="import sys,os,json,time;from pathlib import Path;sys.stdout.write('x'*100000);sys.stdout.flush();Path(sys.argv[1]).write_text(json.dumps({'phase':'ready','processId':os.getpid()}));time.sleep(120)"
            result=pause_and_kill([sys.executable,'-c',code,str(marker)],os.environ.copy(),marker,base/'child.log',wait_seconds=2)
            self.assertTrue(result['reached'],'Undrained child pipes blocked marker creation')
            self.assertEqual(result['boundary']['processId'],result['pid']);self.assertTrue(result['killed'])
            self.assertEqual(result['output'],'x'*100000)

ROOT=Path(__file__).resolve().parents[1]

class NativeSaveSafetyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine=os.environ.get('GENESIS_TEST_GODOT') or shutil.which('godot')
        if not cls.engine:raise unittest.SkipTest('Godot4.7.2 required for native save tests')
        version=subprocess.check_output([cls.engine,'--version'],text=True).strip()
        if not version.startswith('4.7.2.stable.'):raise unittest.SkipTest('Required Godot4.7.2 unavailable; installed '+version)
        cls.crash_engine=cls.engine
        if os.name=='nt' and Path(cls.engine).name.endswith('_console.exe'):
            actual=Path(cls.engine).with_name(Path(cls.engine).name.removesuffix('_console.exe')+'.exe')
            if not actual.is_file():raise AssertionError('Verified Godot process executable missing: '+str(actual))
            cls.crash_engine=str(actual)
        print('GENESIS_CRASH_PROCESS:',cls.crash_engine)
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
                marker=data/'EvidenceGenesis/boundary.json'
                result=pause_and_kill([self.crash_engine,'--headless','--path',str(self.project),*args],self.environment(data),marker,self.base/(kind+'-'+phase+'-child.log'))
                actual=list(data.rglob('*')) if data.exists() else []
                diagnostic=''.join(path.read_text(encoding='utf-8',errors='replace') for path in data.rglob('godot.log')) if data.exists() else ''
                self.assertTrue(result['reached'],'Requested boundary not reached: '+phase+'; files='+str(actual)+'; child='+result['output']+'; log='+diagnostic+'; dialogs='+str(result['dialogs']))
                self.assertTrue(result['killed'],'Child must actually be killed at the boundary')
                self.assertEqual(result['boundary']['phase'],phase)
                self.assertEqual(result['boundary']['processId'],result['pid'],'Kill target must be the actual Godot process')
                if self.evidence:(self.evidence/(kind+'-'+phase+'-killed.log')).write_text(result['output'])
                saved=data/'EvidenceGenesis/crash.json'
                candidate=saved if saved.exists() else Path(str(saved)+'.backup')
                self.assertTrue(candidate.exists(),'No committed save or recovery backup')
                payload=read_save_json(candidate);self.assertIsInstance(payload,dict)
                read_args=['--script','res://tests/save_crash_fixture.gd','--','--read']+(['--index'] if kind=='index' else [])
                text=self.run_engine(kind+'-'+phase+'-read',read_args,data)
                read=json.loads(next(line.removeprefix('CRASH_READ:') for line in text.splitlines() if line.startswith('CRASH_READ:')))
                self.assertTrue(read['ok'])
                self.assertEqual(read['value'],('After' if phase=='after_commit' else 'Before') if kind=='index' else (2 if phase=='after_commit' else 1))
                if kind=='state':self.assertTrue(read['dedupe'],'Recovery awarded duplicate credit')

    def test_interrupted_workshop_writes(self):self.interrupted_writes('state')
    def test_interrupted_profile_index_writes(self):self.interrupted_writes('index')

if __name__=='__main__':unittest.main()
