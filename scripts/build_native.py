"""Build the self-contained Windows game; requires Python and an x64 C compiler on the build machine."""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, tempfile, urllib.request, zipfile
from build_save_adapter import build_adapter
from component_packages import VERSION, emit_candidates, deterministic_zip, verify_full_package_parity
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = '4.7.2-stable'
GODOT_COMMIT = 'ed1daf0bf001b61586d9930840f2f1394092c079'
LLAMA = 'b11429'
LLAMA_COMMIT = 'd81235049384534c167caea52b85a694f6103d14'
RUNTIME_SHA = '1283323272b04cd07905816a597a0da810918102de958f4ff6f7bbaa70ed2efe'
MODEL_SHA = '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db'
MODEL_URL = 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf'
LICENSES = {
 'Godot-LICENSE.txt': f'https://raw.githubusercontent.com/godotengine/godot/{GODOT}/LICENSE.txt',
 'Godot-COPYRIGHT.txt': f'https://raw.githubusercontent.com/godotengine/godot/{GODOT}/COPYRIGHT.txt',
 'llama.cpp-LICENSE.txt': f'https://raw.githubusercontent.com/ggml-org/llama.cpp/{LLAMA}/LICENSE',
 'Qwen-LICENSE.txt': 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/resolve/main/LICENSE',
}

def metadata(url):
 request=urllib.request.Request(url,headers={'User-Agent':'EvidenceGenesis-build/0.4'})
 with urllib.request.urlopen(request,timeout=60) as response:return json.load(response)

def revision(repository):
 value=metadata('https://huggingface.co/api/models/'+repository).get('sha')
 if not isinstance(value,str) or not re.fullmatch('[0-9a-f]{40}',value):raise RuntimeError('Unverified Hugging Face revision: '+repository)
 return value

def provenance_sources():
 if json.loads((ROOT/'package.json').read_text(encoding='utf-8'))['version']!=VERSION or 'Evidence Genesis · '+VERSION not in (ROOT/'native/scripts/game.gd').read_text(encoding='utf-8'):raise RuntimeError('Game application source version does not match candidate version')
 game_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
 if not re.fullmatch('[0-9a-f]{40}',game_commit):raise RuntimeError('Game source commit unavailable')
 subprocess.run(['git','diff','--exit-code','HEAD','--','native','scripts'],cwd=ROOT,check=True,capture_output=True)
 godot_tag=metadata(f'https://api.github.com/repos/godotengine/godot/git/ref/tags/{GODOT}')['object']
 if godot_tag.get('type')!='commit' or godot_tag.get('sha')!=GODOT_COMMIT:raise RuntimeError('Godot tag no longer matches reviewed source commit')
 tag=metadata(f'https://api.github.com/repos/ggml-org/llama.cpp/git/ref/tags/{LLAMA}')['object']
 if tag.get('type')!='commit' or tag.get('sha')!=LLAMA_COMMIT:raise RuntimeError('Runtime tag no longer matches reviewed source commit')
 gguf=revision('Qwen/Qwen2.5-0.5B-Instruct-GGUF');model_license=revision('Qwen/Qwen2.5-0.5B-Instruct')
 immutable_model=MODEL_URL.replace('/resolve/main/','/resolve/'+gguf+'/')
 return {'gameSourceCommit':game_commit,'game':{'version':VERSION,'sourceCommit':game_commit,'peVersionVerified':False,'resourcePresetVersion':'0.3.0.0','resourceModificationEnabled':False},'godot':{'version':GODOT,'sourceCommit':GODOT_COMMIT},'runtime':{'version':LLAMA,'sourceCommit':LLAMA_COMMIT,'archiveUrl':f'https://github.com/ggml-org/llama.cpp/releases/download/{LLAMA}/llama-{LLAMA}-bin-win-cpu-x64.zip','archiveSha256':RUNTIME_SHA},'model':{'version':'Qwen2.5-0.5B-Instruct-Q4_K_M','sourceCommit':gguf,'repository':'Qwen/Qwen2.5-0.5B-Instruct-GGUF','sourceUrl':immutable_model,'sha256':MODEL_SHA,'licenseRepositoryCommit':model_license},'licenses':[]}

def download(url, path):
 path.parent.mkdir(parents=True, exist_ok=True)
 if path.exists(): return path
 request=urllib.request.Request(url, headers={'User-Agent':'EvidenceGenesis-build/0.4'})
 with urllib.request.urlopen(request,timeout=120) as response, path.with_suffix('.download').open('wb') as output:
  shutil.copyfileobj(response,output)
 path.with_suffix('.download').replace(path)
 return path

def verify_godot(path, asset_name, cache):
 sums=download(f'https://github.com/godotengine/godot-builds/releases/download/{GODOT}/SHA512-SUMS.txt',cache/'godot-SHA512-SUMS.txt')
 expected=None
 for line in sums.read_text().splitlines():
  parts=line.split()
  if len(parts)==2 and parts[1].lstrip('*')==asset_name:expected=parts[0]
 if expected is None or hashlib.file_digest(path.open('rb'),'sha512').hexdigest()!=expected:raise RuntimeError('Godot archive checksum mismatch: '+asset_name)

def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as stream:
  for chunk in iter(lambda: stream.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()

def configure_output():
 for stream in (sys.stdout,sys.stderr):
  if hasattr(stream,'reconfigure'):stream.reconfigure(encoding='utf-8')
 os.environ['PYTHONIOENCODING']='utf-8'

def run_game(executable, args, marker=None, isolated=True):
 configure_output()
 with tempfile.TemporaryDirectory(prefix='genesis-test-') as temp:
  env=os.environ.copy()
  if isolated:
   env['XDG_DATA_HOME']=temp
   if os.name=='nt':env['APPDATA']=temp
  log=Path(temp)/'game.log'
  result=subprocess.run([str(executable),'--headless','--log-file',str(log),*args],env=env,text=True,encoding="utf-8",errors="replace",capture_output=True,timeout=240)
  output=result.stdout+result.stderr+(log.read_text(encoding='utf-8',errors='replace') if log.exists() else '')
  print(output[-4000:])
  if result.returncode or 'SCRIPT ERROR' in output or (marker and marker not in output):
   raise RuntimeError('Native test failed: '+str(args))

def package(folder, destination, provenance=None):
 manifest={'version':'0.5.0','saveSchema':4,'godot':GODOT,'llama_cpp':LLAMA,'model':'Qwen2.5-0.5B-Instruct Q4_K_M','model_source':provenance['model']['sourceUrl'] if provenance else MODEL_URL,'files':{}}
 for path in sorted(folder.rglob('*')):
  if path.is_file() and path.name!='SHA256SUMS.json':manifest['files'][path.relative_to(folder).as_posix()]=digest(path)
 (folder/'SHA256SUMS.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
 with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
  for path in sorted(folder.rglob('*')):
   if path.is_file():archive.write(path,'EvidenceGenesis/'+path.relative_to(folder).as_posix())
 with zipfile.ZipFile(destination) as archive:
  if archive.testzip():raise RuntimeError('Archive verification failed')
 print('Package:',destination,'SHA256:',digest(destination))

def main():
 configure_output()
 parser=argparse.ArgumentParser();parser.add_argument('--cache',type=Path,default=Path(tempfile.gettempdir())/'EvidenceGenesis-tools'/GODOT);parser.add_argument('--godot',type=Path);parser.add_argument('--model',type=Path);parser.add_argument('--runtime',type=Path);parser.add_argument('--package-only',action='store_true');parser.add_argument('--output',type=Path,default=ROOT/'build/EvidenceGenesis-Windows-v0.5.0.zip')
 args=parser.parse_args();cache=args.cache;folder=ROOT/'build/windows';folder.mkdir(parents=True,exist_ok=True)
 provenance=None
 if not args.package_only:
  provenance=provenance_sources()
  if folder.exists():shutil.rmtree(folder)
  folder.mkdir(parents=True)
  godot=args.godot
  if godot is None:
   platform='win64.exe' if os.name=='nt' else 'linux.x86_64'
   archive=download(f'https://github.com/godotengine/godot-builds/releases/download/{GODOT}/Godot_v{GODOT}_{platform}.zip',cache/'godot.zip')
   verify_godot(archive,f'Godot_v{GODOT}_{platform}.zip',cache)
   with zipfile.ZipFile(archive) as z:z.extractall(cache/'editor')
   candidates=list((cache/'editor').glob('*console.exe' if os.name=='nt' else 'Godot*'))
   godot=candidates[0]
   if os.name!='nt':godot.chmod(0o755)
  templates=download(f'https://github.com/godotengine/godot-builds/releases/download/{GODOT}/Godot_v{GODOT}_export_templates.tpz',cache/'templates.tpz')
  verify_godot(templates,f'Godot_v{GODOT}_export_templates.tpz',cache)
  version=subprocess.check_output([str(godot),'--version'],text=True).strip()
  if not version.startswith('4.7.2.stable.'):raise RuntimeError('Expected Godot4.7.2; got '+version)
  base=Path(os.environ.get('APPDATA',Path.home()/'.local/share'))/'Godot' if os.name=='nt' else Path.home()/'.local/share/godot'
  target=base/'export_templates/4.7.2.stable';target.mkdir(parents=True,exist_ok=True)
  with zipfile.ZipFile(templates) as z:
   for name in ['windows_release_x86_64.exe','windows_debug_x86_64.exe','version.txt']:(target/name).write_bytes(z.read('templates/'+name))
  adapter=build_adapter(ROOT/'native')
  provenance['saveAdapter']={'kind':'first-party Godot C ABI','platform':os.name,'library':adapter.name,'sha256':digest(adapter),'godotSourceCommit':GODOT_COMMIT,'compilerPinVerified':False}
  run_game(godot,['--path',str(ROOT/'native'),'--editor','--import','--quit'],isolated=False)
  run_game(godot,['--path',str(ROOT/'native'),'--script','res://tests/save_adapter_test.gd'],'GENESIS_SAVE_ADAPTER_OK')
  test_env=os.environ.copy();test_env['GENESIS_TEST_GODOT']=str(godot)
  subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-p','test_*save*.py','-v','-f'],cwd=ROOT,env=test_env,check=True,timeout=240)
  run_game(godot,['--path',str(ROOT/'native'),'--script','res://tests/state_test.gd'],'GENESIS_STATE_TEST_OK')
  run_game(godot,['--path',str(ROOT/'native'),'--script','res://tests/startup_test.gd','--','--no-brain'],'GENESIS_STARTUP_TEST_OK')
  run_game(godot,['--path',str(ROOT/'native'),'--export-release','Windows Desktop',str(folder/'EvidenceGenesis.exe')],isolated=False)
  if os.name=='nt' and not (folder/'genesis_save.dll').is_file():raise RuntimeError('Export omitted the required native save adapter')
  runtime=args.runtime or download(f'https://github.com/ggml-org/llama.cpp/releases/download/{LLAMA}/llama-{LLAMA}-bin-win-cpu-x64.zip',cache/'llama-win.zip')
  if digest(runtime)!=RUNTIME_SHA:raise RuntimeError('Runtime checksum mismatch')
  with zipfile.ZipFile(runtime) as z:z.extractall(folder/'brain')
  model=args.model or download(provenance['model']['sourceUrl'],cache/'genesis.gguf')
  if digest(model)!=MODEL_SHA:raise RuntimeError('Model checksum mismatch')
  (folder/'model').mkdir(exist_ok=True);shutil.copyfile(model,folder/'model/genesis.gguf')
  (folder/'licenses').mkdir(exist_ok=True)
  license_urls=dict(LICENSES)
  for name in ['Godot-LICENSE.txt','Godot-COPYRIGHT.txt']:license_urls[name]=license_urls[name].replace('/'+GODOT+'/', '/'+GODOT_COMMIT+'/')
  license_urls['llama.cpp-LICENSE.txt']=f'https://raw.githubusercontent.com/ggml-org/llama.cpp/{LLAMA_COMMIT}/LICENSE'
  license_urls['Qwen-LICENSE.txt']='https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/resolve/'+provenance['model']['licenseRepositoryCommit']+'/LICENSE'
  for name,url in license_urls.items():
   notice=download(url,cache/(hashlib.sha256(url.encode()).hexdigest()[:12]+'-'+name));shutil.copyfile(notice,folder/'licenses'/name)
   kind='runtime' if name.startswith('llama') else ('model' if name.startswith('Qwen') else 'game')
   provenance['licenses'].append({'name':name,'component':kind,'sourceUrl':url,'sha256':digest(notice),'packagePath':'licenses/'+name})
  if os.name=='nt':
   run_game(folder/'EvidenceGenesis.exe',['--','--no-brain','--smoke-test'],'GENESIS_NATIVE_SMOKE_OK')
   run_game(folder/'EvidenceGenesis.exe',['--','--ai-smoke-test'],'GENESIS_AI_SMOKE_OK')
 shutil.copyfile(ROOT/'native/PLAYER_README.txt',folder/'START-HERE.txt')
 if provenance is not None:(folder/'build-info.json').write_text(json.dumps({'schema':1,'product':'genesis','version':VERSION,'sourceCommit':provenance['gameSourceCommit'],'saveSchema':4,'minimumHubVersion':'0.3.0','godot':GODOT},indent=2,sort_keys=True)+'\n',encoding='utf-8')
 for path in folder.glob('*.tmp-*'):path.unlink()
 args.output.parent.mkdir(parents=True,exist_ok=True);package(folder,args.output,provenance)
 if provenance is not None:
  if os.name!='nt':raise RuntimeError('Component candidates require Windows packaged-game and real bundled-model checks')
  stages={kind:ROOT/'build/component-staging'/kind for kind in ['game','runtime','model']}
  for target in stages.values():
   if target.exists():shutil.rmtree(target)
   target.mkdir(parents=True)
  for item in folder.iterdir():
   if item.name in ['brain','model','licenses']:continue
   if item.is_file() and item.name!='SHA256SUMS.json':shutil.copyfile(item,stages['game']/item.name)
  shutil.copytree(folder/'brain',stages['runtime'],dirs_exist_ok=True);shutil.copytree(folder/'model',stages['model'],dirs_exist_ok=True)
  for notice in provenance['licenses']:
   target=stages[notice['component']]/notice['packagePath'];target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(folder/'licenses'/notice['name'],target)
  provenance['fullPackage']={'path':args.output.name,'size':args.output.stat().st_size,'sha256':digest(args.output),'files':[{'path':'EvidenceGenesis/'+item.relative_to(folder).as_posix(),'size':item.stat().st_size,'sha256':digest(item)} for item in sorted(folder.rglob('*')) if item.is_file()]}
  provenance['verification']={'godotImport':True,'stateTests':True,'startupRestoreTests':True,'packagedPanelSmoke':True,'actualBundledModelGeneration':True,'nativeSaveAdapterTests':True}
  components=ROOT/'build/components'
  if components.exists():shutil.rmtree(components)
  report=emit_candidates(stages,components,provenance)
  facts=json.loads(report.read_text(encoding='utf-8'))
  verify_full_package_parity(args.output,facts['packages'],provenance)
  with tempfile.TemporaryDirectory(prefix='genesis-reproducibility-') as temp:
   for entry in facts['packages']:
    repeated=deterministic_zip(stages[entry['kind']],Path(temp)/(entry['kind']+'.zip'))
    if repeated['sha256']!=entry['sha256'] or repeated['size']!=entry['size']:raise RuntimeError('Component packing was not reproducible')
  facts['provenance']['verification']['fullPackageComponentByteParity']=True
  facts['provenance']['verification']['repeatedArchiveBytesIdentical']=True
  report.write_text(json.dumps(facts,indent=2,sort_keys=True)+'\n',encoding='utf-8')
  print('GENESIS_COMPONENT_PARITY_OK: game/runtime/model actual full-package bytes and deterministic archives verified')
  print('Unsigned component candidate report:',report)
 else:print('Component candidates not emitted: run the verified Windows build first.')

if __name__=='__main__':main()
