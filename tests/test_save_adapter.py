"""Actual OS sync/rename proof, not a physical power-loss simulation."""
import ctypes
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from build_save_adapter import build_adapter

ROOT=Path(__file__).resolve().parents[1]

class SaveAdapterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='genesis-native-io-')
        cls.base=Path(cls.temp.name);cls.project=cls.base/'native'
        shutil.copytree(ROOT/'native/durability',cls.project/'durability')
        cls.library=ctypes.CDLL(str(build_adapter(cls.project)))
        cls.bind(cls.library)

    @classmethod
    def bind(cls,library):
        library.genesis_sync_file.argtypes=[ctypes.c_char_p];library.genesis_sync_file.restype=ctypes.c_int
        library.genesis_replace_file.argtypes=[ctypes.c_char_p,ctypes.c_char_p];library.genesis_replace_file.restype=ctypes.c_int

    @classmethod
    def tearDownClass(cls):
        if os.name=='nt':
            # Windows holds DLL mappings; explicit unload before deleting test tree.
            import _ctypes
            _ctypes.FreeLibrary(cls.library._handle)
        cls.temp.cleanup()

    def setUp(self):
        self.case=Path(tempfile.mkdtemp(dir=self.base));self.active=self.case/'ورکشاپ 🐾.json';self.stage=self.case/'stage.json'
        self.active.write_bytes(b'old');self.stage.write_bytes(b'new')

    def replace(self):return self.library.genesis_replace_file(os.fsencode(self.stage),os.fsencode(self.active))

    def test_build_paths_preserve_unicode_and_literal_percent(self):
        project=self.case/'ورکشاپ %GENESIS_UNUSED_NAME% 🐾'
        shutil.copytree(ROOT/'native/durability',project/'durability')
        output=build_adapter(project)
        self.assertTrue(output.is_file());self.assertGreater(output.stat().st_size,0)

    def test_unicode_replacement_and_sync(self):
        self.assertEqual(self.library.genesis_sync_file(str(self.stage).encode('utf-8')),0)
        # Always UTF8 on Windows too; filesystem encoding there is UTF8 in Python3.12.
        self.assertEqual(self.replace(),0)
        self.assertEqual(self.active.read_bytes(),b'new');self.assertFalse(self.stage.exists())

    def test_missing_source_directory_and_cross_directory_refuse_without_mutation(self):
        self.stage.unlink();self.assertNotEqual(self.replace(),0);self.assertEqual(self.active.read_bytes(),b'old')
        self.stage.mkdir();self.assertNotEqual(self.replace(),0);self.assertEqual(self.active.read_bytes(),b'old')
        self.assertNotEqual(self.library.genesis_sync_file(os.fsencode(self.stage)),0)
        other=self.case/'other';other.mkdir();source=other/'source';source.write_bytes(b'new')
        self.assertNotEqual(self.library.genesis_replace_file(os.fsencode(source),os.fsencode(self.active)),0)
        self.assertEqual(self.active.read_bytes(),b'old');self.assertEqual(source.read_bytes(),b'new')

    def test_directory_destination_refuses_and_retains_stage(self):
        self.active.unlink();self.active.mkdir();self.assertNotEqual(self.replace(),0)
        self.assertTrue(self.active.is_dir());self.assertEqual(self.stage.read_bytes(),b'new')

    @unittest.skipIf(os.name=='nt','POSIX symbolic-link creation/semantics')
    def test_symlink_files_refuse_without_touching_target(self):
        self.stage.unlink();self.stage.symlink_to(self.active)
        self.assertNotEqual(self.library.genesis_sync_file(os.fsencode(self.stage)),0)
        self.assertNotEqual(self.replace(),0);self.assertEqual(self.active.read_bytes(),b'old')
        self.stage.unlink();self.stage.write_bytes(b'new');target=self.case/'target';target.write_bytes(b'original')
        self.active.unlink();self.active.symlink_to(target)
        self.assertNotEqual(self.replace(),0);self.assertEqual(target.read_bytes(),b'original');self.assertTrue(self.active.is_symlink())

    def test_readers_observe_complete_old_or_new_bytes(self):
        old=b'a'*65536;new=b'b'*65536;self.active.write_bytes(old)
        stop=threading.Event();errors=[];reads=[]
        def reader():
            while not stop.is_set():
                try:
                    value=self.active.read_bytes();reads.append(1)
                    if value not in (old,new):errors.append('partial data')
                except PermissionError:
                    if os.name!='nt':errors.append('unexpected denied read')
                except OSError as error:errors.append(str(error))
        worker=threading.Thread(target=reader);worker.start()
        try:
            for i in range(100):
                self.stage.write_bytes(new if i%2==0 else old)
                status=self.replace()
                # Windows may refuse a rename while a reader owns a non-delete-sharing handle.
                if status==1:self.assertTrue(self.stage.exists())
                else:self.assertEqual(status,0)
        finally:stop.set();worker.join(timeout=5)
        self.assertFalse(worker.is_alive());self.assertTrue(reads);self.assertEqual(errors,[])

    @unittest.skipUnless(os.name=='nt','Actual Windows locked-destination refusal')
    def test_windows_locked_destination_preserves_original_and_stage(self):
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p]
        kernel.CreateFileW.restype=ctypes.c_void_p;kernel.CloseHandle.argtypes=[ctypes.c_void_p]
        handle=kernel.CreateFileW(str(self.active),0x80000000,0,None,3,0,None)
        self.assertNotEqual(handle,ctypes.c_void_p(-1).value)
        try:self.assertEqual(self.replace(),1)
        finally:kernel.CloseHandle(handle)
        self.assertEqual(self.active.read_bytes(),b'old');self.assertEqual(self.stage.read_bytes(),b'new')

    @unittest.skipIf(os.name=='nt','POSIX real fsync error injection')
    def test_file_and_directory_sync_errors_report_distinct_commit_states(self):
        wrapper=self.case/'fault.c'
        wrapper.write_text('''#define _GNU_SOURCE
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>
int mode=0;
int genesis_test_fsync(int fd) {
 struct stat s; if (fstat(fd,&s)) return -1;
 if ((mode==1 && S_ISREG(s.st_mode)) || (mode==2 && S_ISDIR(s.st_mode))) { errno=EIO;return -1; }
 return (int)syscall(SYS_fsync,fd);
}
''')
        library=self.case/'fault.so'
        subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-shared','-fPIC','-Dfsync=genesis_test_fsync',str(ROOT/'native/durability/save_platform.c'),str(wrapper),'-o',str(library)],check=True)
        fault=ctypes.CDLL(str(library));self.bind(fault);mode=ctypes.c_int.in_dll(fault,'mode')
        mode.value=1;self.assertEqual(fault.genesis_replace_file(os.fsencode(self.stage),os.fsencode(self.active)),1)
        self.assertEqual(self.active.read_bytes(),b'old');self.assertEqual(self.stage.read_bytes(),b'new')
        mode.value=2;self.assertEqual(fault.genesis_replace_file(os.fsencode(self.stage),os.fsencode(self.active)),2)
        self.assertEqual(self.active.read_bytes(),b'new');self.assertFalse(self.stage.exists())

if __name__=='__main__':unittest.main()
