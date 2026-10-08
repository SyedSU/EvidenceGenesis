"""Build the self-contained Windows game; requires Python only on the build machine."""
import argparse, hashlib, json, os, shutil, subprocess, tempfile, urllib.request, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT = '4.7.2-stable'
LLAMA = 'b11429'
MODEL_SHA = '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db'
MODEL_URL = 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf'
LICENSES = {
 'Godot-LICENSE.txt': f'https://raw.githubusercontent.com/godotengine/godot/{GODOT}/LICENSE.txt',
 'Godot-COPYRIGHT.txt': f'https://raw.githubusercontent.com/godotengine/godot/{GODOT}/COPYRIGHT.txt',
 'llama.cpp-LICENSE.txt': f'https://raw.githubusercontent.com/ggml-org/llama.cpp/{LLAMA}/LICENSE',
 'Qwen-LICENSE.txt': 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/resolve/main/LICENSE',
}

def download(url, path):
 path.parent.mkdir(parents=True, exist_ok=True)
 if path.exists(): return path
 request=urllib.request.Request(url, headers={'User-Agent':'EvidenceGenesis-build/0.2'})
 with urllib.request.urlopen(request,timeout=120) as response, path.with_suffix('.download').open('wb') as output:
  shutil.copyfileobj(response,output)
 path.with_suffix('.download').replace(path)
 return path

def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as stream:
  for chunk in iter(lambda: stream.read(1024*1024),b''):h.update(chunk)
 return h.hexdigest()

def run_game(executable, args, marker=None):
 with tempfile.TemporaryDirectory(prefix='genesis-test-') as temp:
  env=os.environ.copy();env['XDG_DATA_HOME']=temp
  if os.name=='nt':env['APPDATA']=temp
  log=Path(temp)/'game.log'
  result=subprocess.run([str(executable),'--headless','--log-file',str(log),*args],env=env,text=True,capture_output=True,timeout=240)
  output=result.stdout+result.stderr+(log.read_text(encoding='utf-8',errors='replace') if log.exists() else '')
  print(output[-4000:])
  if result.returncode or 'SCRIPT ERROR' in output or (marker and marker not in output):
   raise RuntimeError('Native test failed: '+str(args))

def package(folder, destination):
 manifest={'version':'0.2.0','godot':GODOT,'llama_cpp':LLAMA,'model':'Qwen2.5-0.5B-Instruct Q4_K_M','model_source':MODEL_URL,'files':{}}
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
 parser=argparse.ArgumentParser();parser.add_argument('--cache',type=Path,default=ROOT/'build/tools');parser.add_argument('--godot',type=Path);parser.add_argument('--model',type=Path);parser.add_argument('--runtime',type=Path);parser.add_argument('--package-only',action='store_true');parser.add_argument('--output',type=Path,default=ROOT/'build/EvidenceGenesis-Windows-v0.2.0.zip')
 args=parser.parse_args();cache=args.cache;folder=ROOT/'build/windows';folder.mkdir(parents=True,exist_ok=True)
 if not args.package_only:
  godot=args.godot
  if godot is None:
   platform='win64.exe' if os.name=='nt' else 'linux.x86_64'
   archive=download(f'https://github.com/godotengine/godot-builds/releases/download/{GODOT}/Godot_v{GODOT}_{platform}.zip',cache/'godot.zip')
   with zipfile.ZipFile(archive) as z:z.extractall(cache/'editor')
   candidates=list((cache/'editor').glob('*console.exe' if os.name=='nt' else 'Godot*'))
   godot=candidates[0]
   if os.name!='nt':godot.chmod(0o755)
  templates=download(f'https://github.com/godotengine/godot-builds/releases/download/{GODOT}/Godot_v{GODOT}_export_templates.tpz',cache/'templates.tpz')
  base=Path(os.environ.get('APPDATA',Path.home()/'.local/share'))/'Godot' if os.name=='nt' else Path.home()/'.local/share/godot'
  target=base/'export_templates/4.7.2.stable';target.mkdir(parents=True,exist_ok=True)
  with zipfile.ZipFile(templates) as z:
   for name in ['windows_release_x86_64.exe','windows_debug_x86_64.exe','version.txt']:(target/name).write_bytes(z.read('templates/'+name))
  run_game(godot,['--path',str(ROOT/'native'),'--editor','--import','--quit'])
  run_game(godot,['--path',str(ROOT/'native'),'--script','res://tests/state_test.gd'],'GENESIS_STATE_TEST_OK')
  run_game(godot,['--path',str(ROOT/'native'),'--export-release','Windows Desktop',str(folder/'EvidenceGenesis.exe')])
  runtime=args.runtime or download(f'https://github.com/ggml-org/llama.cpp/releases/download/{LLAMA}/llama-{LLAMA}-bin-win-cpu-x64.zip',cache/'llama-win.zip')
  with zipfile.ZipFile(runtime) as z:z.extractall(folder/'brain')
  model=args.model or download(MODEL_URL,cache/'genesis.gguf')
  if digest(model)!=MODEL_SHA:raise RuntimeError('Model checksum mismatch')
  (folder/'model').mkdir(exist_ok=True);shutil.copyfile(model,folder/'model/genesis.gguf')
  (folder/'licenses').mkdir(exist_ok=True)
  for name,url in LICENSES.items():shutil.copyfile(download(url,cache/name),folder/'licenses'/name)
  if os.name=='nt':
   run_game(folder/'EvidenceGenesis.exe',['--','--no-brain','--smoke-test'],'GENESIS_NATIVE_SMOKE_OK')
   run_game(folder/'EvidenceGenesis.exe',['--','--ai-smoke-test'],'GENESIS_AI_SMOKE_OK')
 shutil.copyfile(ROOT/'native/PLAYER_README.txt',folder/'START-HERE.txt')
 for path in folder.glob('*.tmp-*'):path.unlink()
 args.output.parent.mkdir(parents=True,exist_ok=True);package(folder,args.output)

if __name__=='__main__':main()
