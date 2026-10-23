import hashlib,importlib.util,json,tempfile,unittest,zipfile
from pathlib import Path

class ReviewInspectionTests(unittest.TestCase):
 def module(self):
  path=Path(__file__).parents[1]/'scripts/inspect_review_build.py';self.assertTrue(path.is_file(),'Downloaded-package inspector required')
  spec=importlib.util.spec_from_file_location('inspection',path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
 def test_downloaded_asset_hashes_are_checked(self):
  module=self.module()
  with tempfile.TemporaryDirectory() as tmp:
   root=Path(tmp);path=root/'file.zip';path.write_bytes(b'exact bytes')
   facts=[{'name':path.name,'size':11,'sha256':'sha256:'+hashlib.sha256(path.read_bytes()).hexdigest()}]
   module.verify_downloads(root,facts)
   path.write_bytes(b'other bytes')
   with self.assertRaises(ValueError):module.verify_downloads(root,facts)
 def test_zip_inventory_reads_real_bytes_and_rejects_traversal_aliases(self):
  module=self.module()
  with tempfile.TemporaryDirectory() as tmp:
   path=Path(tmp)/'archive.zip'
   with zipfile.ZipFile(path,'w') as archive:archive.writestr('folder/file.txt',b'exact bytes')
   self.assertEqual(module.zip_inventory(path),[{'path':'folder/file.txt','size':11,'sha256':hashlib.sha256(b'exact bytes').hexdigest()}])
   for name in ['../bad','/root','a\\bad','C:/bad','a//bad','x/CON.txt','x/file:stream','x/file.','x/./file','x/COM¹.txt','LPT²' ]:
    with self.subTest(name=name):
     with zipfile.ZipFile(path,'w') as archive:archive.writestr(name,b'x')
     with self.assertRaises(ValueError):module.zip_inventory(path)
 def test_zip_rejects_case_collisions_and_symlinks(self):
  module=self.module()
  with tempfile.TemporaryDirectory() as tmp:
   path=Path(tmp)/'archive.zip'
   with zipfile.ZipFile(path,'w') as archive:
    archive.writestr('file',b'a');archive.writestr('FILE',b'b')
   with self.assertRaises(ValueError):module.zip_inventory(path)
   with zipfile.ZipFile(path,'w') as archive:
    info=zipfile.ZipInfo('link');info.create_system=3;info.external_attr=0o120777<<16;archive.writestr(info,b'target')
   with self.assertRaises(ValueError):module.zip_inventory(path)
 def test_zip_rejects_windows_reparse_attribute(self):
  module=self.module()
  with tempfile.TemporaryDirectory() as tmp:
   path=Path(tmp)/'archive.zip'
   with zipfile.ZipFile(path,'w') as archive:
    info=zipfile.ZipInfo('file');info.create_system=0;info.external_attr=0x400;archive.writestr(info,b'target')
   with self.assertRaises(ValueError):module.zip_inventory(path)
 def test_source_bound_receipt_rejects_relabelled_build(self):
  module=self.module();lock={'repository':'SyedSU/EvidenceGenesis','sourceCommit':'a'*40,'runId':1,'assets':[{'name':'file.zip','size':1,'sha256':'sha256:'+'b'*64}]}
  receipt={'repository':lock['repository'],'sourceCommit':lock['sourceCommit'],'runId':'1','publicationAuthorized':False,'files':[{'name':'file.zip','size':1,'sha256':'b'*64}]}
  module.verify_receipt(receipt,lock)
  receipt['sourceCommit']='c'*40
  with self.assertRaises(ValueError):module.verify_receipt(receipt,lock)

if __name__=='__main__':unittest.main()
