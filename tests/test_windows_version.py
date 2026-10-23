"""Version-resource serialization and actual Windows API round-trip."""
import importlib.util
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))

class WindowsVersionTests(unittest.TestCase):
 def module(self):
  path=Path(__file__).resolve().parents[1]/'scripts/windows_version.py'
  self.assertTrue(path.is_file(),'Windows version writer is required')
  spec=importlib.util.spec_from_file_location('windows_version',path)
  module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  return module

 def test_resource_contains_fixed_and_string_product_identity(self):
  module=self.module();data=module.version_resource('0.5.0')
  self.assertEqual(struct.unpack_from('<HHH',data),(len(data),52,0))
  key='VS_VERSION_INFO\0'.encode('utf-16le');self.assertEqual(data[6:6+len(key)],key)
  offset=(6+len(key)+3)&~3
  fixed=struct.unpack_from('<13I',data,offset)
  self.assertEqual(fixed[:6],(0xfeef04bd,0x10000,5,0,5,0))
  for text in ['Evidence Genesis','FileVersion','ProductVersion','0.5.0.0','040904b0']:
   self.assertIn((text+'\0').encode('utf-16le'),data)
  self.assertEqual(module.version_tuple('65535.2.0.4'),(65535,2,0,4))

 def test_rejects_ambiguous_or_out_of_range_versions(self):
  module=self.module()
  for value in ['0.5','0.5.0-beta','0.5.0.0.1','65536.0.0','-1.0.0','01.5.0',' 0.5.0',None]:
   with self.subTest(value=value),self.assertRaises(ValueError):module.version_resource(value)

 @unittest.skipUnless(os.name=='nt','Actual Windows resource APIs required')
 def test_actual_unicode_path_update_and_readback(self):
  module=self.module()
  with tempfile.TemporaryDirectory(prefix='genesis-version-') as temp:
   target=Path(temp)/'ورژن-test.exe';shutil.copyfile(sys.executable,target)
   module.write_version(target,'0.5.0')
   self.assertEqual(module.read_version(target),(0,5,0,0))
   module.write_version(target,'1.2.3.4')
   self.assertEqual(module.read_version(target),(1,2,3,4))
   # Independent Windows string-table query catches malformed child lengths,
   # Unicode value lengths, language/code-page IDs and resource alignment.
   import ctypes
   from ctypes import wintypes
   api=ctypes.WinDLL('version',use_last_error=True)
   api.GetFileVersionInfoSizeW.argtypes=[wintypes.LPCWSTR,ctypes.POINTER(wintypes.DWORD)];api.GetFileVersionInfoSizeW.restype=wintypes.DWORD
   api.GetFileVersionInfoW.argtypes=[wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p];api.GetFileVersionInfoW.restype=wintypes.BOOL
   api.VerQueryValueW.argtypes=[ctypes.c_void_p,wintypes.LPCWSTR,ctypes.POINTER(ctypes.c_void_p),ctypes.POINTER(wintypes.UINT)];api.VerQueryValueW.restype=wintypes.BOOL
   unused=wintypes.DWORD();data=ctypes.create_string_buffer(api.GetFileVersionInfoSizeW(str(target),ctypes.byref(unused)))
   self.assertTrue(api.GetFileVersionInfoW(str(target),0,len(data),data))
   for key,expected in [('FileVersion','1.2.3.4'),('ProductVersion','1.2.3.4'),('ProductName','Evidence Genesis')]:
    pointer=ctypes.c_void_p();length=wintypes.UINT()
    self.assertTrue(api.VerQueryValueW(data,'\\StringFileInfo\\040904b0\\'+key,ctypes.byref(pointer),ctypes.byref(length)))
    self.assertEqual(ctypes.wstring_at(pointer),expected)

if __name__=='__main__':unittest.main()
