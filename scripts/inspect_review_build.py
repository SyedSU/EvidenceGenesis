"""Read-only transport/package acceptance for a pinned private review build.

Download into a fresh workspace, validate bytes before extraction/execution, then
exercise those downloaded Windows packages. No signing/publication/lock promotion.
"""
import hashlib,json,os,re,stat,subprocess,tempfile,unicodedata,zipfile
from pathlib import Path


def sha256(path):
 with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def safe_name(name):
 if not isinstance(name,str) or not name or len(name)>240 or unicodedata.normalize('NFC',name)!=name or '\\' in name or name.startswith('/'):
  raise ValueError('Unsafe archive path')
 for part in name.split('/'):
  if part in ('','.','..') or part[-1:] in (' ','.') or any(ord(c)<32 or c in ':<>"|?*' for c in part) or re.fullmatch(r'(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\..*)?',part,re.I):
   raise ValueError('Unsafe Windows archive path')
 return name


def zip_inventory(path):
 result=[];seen=set();total=0
 with zipfile.ZipFile(path) as archive:
  if not 0<len(archive.infolist())<=2000:raise ValueError('Archive member count exceeds bound')
  for info in archive.infolist():
   name=safe_name(info.orig_filename)
   if name!=info.filename:raise ValueError('Archive path normalization is refused')
   key=name.casefold();mode=stat.S_IFMT(info.external_attr>>16)
   if key in seen or info.external_attr&0x400 or info.is_dir() or mode not in (0,stat.S_IFREG) or info.flag_bits&1 or info.compress_type not in (0,8) or info.file_size>1024**3:
    raise ValueError('Unsafe or duplicate archive entry')
   seen.add(key);total+=info.file_size
   if total>2*1024**3:raise ValueError('Unpacked archive exceeds bound')
   with archive.open(info) as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
   result.append({'path':name,'size':info.file_size,'sha256':digest})
 return sorted(result,key=lambda row:row['path'])


def verify_downloads(root,assets):
 root=Path(root)
 if {path.name for path in root.iterdir()}!={row['name'] for row in assets}:raise ValueError('Downloaded asset inventory differs')
 for row in assets:
  name=safe_name(row['name']);path=root/name
  if '/' in name or path.is_symlink() or not path.is_file() or path.stat().st_size!=row['size'] or 'sha256:'+sha256(path)!=row['sha256']:
   raise ValueError('Downloaded asset size/SHA256 mismatch: '+name)


def verify_receipt(receipt,lock):
 if receipt.get('repository')!=lock['repository'] or receipt.get('sourceCommit')!=lock['sourceCommit'] or str(receipt.get('runId'))!=str(lock['runId']) or receipt.get('publicationAuthorized') is not False:
  raise ValueError('Downloaded receipt source identity differs')
 expected={row['name']:(row['size'],row['sha256']) for row in lock['assets'] if row['name']!='review-build.json'}
 actual={row['name']:(row['size'],'sha256:'+row['sha256']) for row in receipt.get('files',[])}
 if actual!=expected or len(actual)!=len(receipt.get('files',[])):raise ValueError('Receipt inventory differs from pinned assets')


def inspect_genesis(downloads,lock,work):
 from component_packages import verify_full_package_parity
 from build_native import run_game
 from windows_version import read_version
 report=json.loads((downloads/'genesis-candidate-report.json').read_text(encoding='utf-8'))
 if report.get('sourceCommit')!=lock['sourceCommit'] or report.get('version')!='0.5.0' or report.get('saveSchema')!=4:
  raise ValueError('Candidate report does not identify pinned game')
 provenance=report['provenance']
 if provenance['gameSourceCommit']!=lock['sourceCommit'] or provenance['game'].get('peVersionVerified') is not True:
  raise ValueError('Candidate provenance lacks actual executable identity')
 checks=('godotImport','stateTests','startupRestoreTests','packagedPanelSmoke','actualBundledModelGeneration','nativeSaveAdapterTests','fullPackageComponentByteParity','repeatedArchiveBytesIdentical')
 if any(provenance['verification'].get(key) is not True for key in checks):raise ValueError('Candidate build acceptance incomplete')
 if {entry['kind'] for entry in report['packages']}!={'game','runtime','model'} or len(report['packages'])!=3:raise ValueError('Component set mismatch')
 for entry in report['packages']:
  name=safe_name(entry['path'])
  if '/' in name or zip_inventory(downloads/name)!=sorted(entry['files'],key=lambda row:row['path']) or sha256(downloads/name)!=entry['sha256']:
   raise ValueError('Downloaded component inventory differs')
 full=downloads/'EvidenceGenesis-Windows-v0.5.0.zip';inventory=zip_inventory(full)
 verify_full_package_parity(full,report['packages'],provenance)
 with zipfile.ZipFile(full) as archive:
  manifest=json.loads(archive.read('EvidenceGenesis/SHA256SUMS.json'))
  actual={row['path'].removeprefix('EvidenceGenesis/'):row['sha256'] for row in inventory if row['path']!='EvidenceGenesis/SHA256SUMS.json'}
  if manifest['files']!=actual or manifest['version']!='0.5.0' or manifest['saveSchema']!=4:raise ValueError('Full package checksum manifest differs')
  # All paths, aliases, types, sizes and bytes checked before any extraction.
  archive.extractall(work)
 game=work/'EvidenceGenesis';executable=game/'EvidenceGenesis.exe'
 if read_version(executable)!=(0,5,0,0):raise ValueError('Downloaded executable version differs')
 for notice in provenance['licenses']:
  path=game/'licenses'/Path(notice['packagePath']).name
  if not path.is_file() or not path.stat().st_size or sha256(path)!=notice['sha256']:raise ValueError('Downloaded third-party notice differs')
 run_game(executable,['--','--no-brain','--smoke-test'],'GENESIS_NATIVE_SMOKE_OK')
 run_game(executable,['--','--ai-smoke-test'],'GENESIS_AI_SMOKE_OK')
 return {'zipFiles':len(inventory),'componentByteParity':True,'checksumManifest':True,'thirdPartyNoticeBytes':True,'downloadedPeVersion':'0.5.0.0','downloadedNativeSmoke':True,'downloadedRealModelGeneration':True}


def main():
 from store_review_build import api,validate_repository,verify_release
 root=Path(__file__).resolve().parents[1]
 lock=json.loads((root/'review/inspection-lock.json').read_text(encoding='utf-8'))
 if os.environ.get('GITHUB_REPOSITORY')!=lock['repository'] or os.environ.get('GITHUB_REF')!='refs/heads/main' or os.name!='nt':raise ValueError('Exact main Windows inspection required')
 validate_repository(api('repos/'+lock['repository']),lock['repository'])
 release=api('repos/'+lock['repository']+'/releases/'+str(lock['release']['id']))
 if release['tag_name']!=lock['release']['tag']:raise ValueError('Pinned draft tag changed')
 verify_release(release,[{'name':a['name'],'size':a['size'],'sha256':a['sha256'].removeprefix('sha256:')} for a in lock['assets']],lock['sourceCommit'])
 with tempfile.TemporaryDirectory(prefix='review-inspection-') as temp:
  downloads=Path(temp)/'downloads';downloads.mkdir();work=Path(temp)/'unpacked';work.mkdir()
  subprocess.run(['gh','release','download',lock['release']['tag'],'--repo',lock['repository'],'--dir',str(downloads)],check=True)
  verify_downloads(downloads,lock['assets']);verify_receipt(json.loads((downloads/'review-build.json').read_text(encoding='utf-8')),lock)
  if lock['product']=='genesis':result=inspect_genesis(downloads,lock,work)
  else:
   import shutil
   artifacts=root/'artifacts';artifacts.mkdir(exist_ok=True)
   installer=downloads/'EvidenceNeuterHub-Setup-0.3.0.exe';shutil.copyfile(installer,artifacts/installer.name)
   subprocess.run(['pwsh','-NoProfile','-File',str(root/'installer/smoke.ps1')],cwd=root,check=True,timeout=240)
   result={'downloadedInstallerNativeSmoke':True,'downloadedInstallerSha256':sha256(installer)}
  result.update({'repository':lock['repository'],'sourceCommit':lock['sourceCommit'],'originalRunId':lock['runId'],'releaseId':lock['release']['id'],'downloadedAssetsVerified':len(lock['assets']),'inspectionRunId':os.environ['GITHUB_RUN_ID'],'publicDownloads':False,'productionPublicationAuthorized':False,'signerAcceptance':'UNRUN','targetDeviceAcceptance':'UNRUN','androidAcceptance':'UNRUN'})
  print('DOWNLOADED_PACKAGE_INSPECTION_JSON:'+json.dumps(result,sort_keys=True))

if __name__=='__main__':main()
