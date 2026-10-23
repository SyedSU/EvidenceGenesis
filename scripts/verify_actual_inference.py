"""Real pinned model proof; fixtures never satisfy this command."""
import hashlib,json,os,re,subprocess,sys,tempfile,urllib.request,zipfile
from pathlib import Path
from build_native import MODEL_SHA,GODOT,GODOT_COMMIT,download,metadata,revision,run_game
from build_save_adapter import build_adapter

ROOT=Path(__file__).resolve().parents[1]

def main():
 if not sys.platform.startswith('linux'):raise RuntimeError('This host inference harness requires Linux x64')
 library=Path(os.environ['GENESIS_AI_LIBRARY']).resolve()
 if not library.is_file():raise RuntimeError('Real native inference build is required')
 with tempfile.TemporaryDirectory(prefix='genesis-real-ai-') as temp:
  work=Path(temp);model_commit=revision('Qwen/Qwen2.5-0.5B-Instruct-GGUF')
  model=download('https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/'+model_commit+'/qwen2.5-0.5b-instruct-q4_k_m.gguf',work/'genesis.gguf')
  if hashlib.sha256(model.read_bytes()).hexdigest()!=MODEL_SHA:raise RuntimeError('Actual model SHA256 differs')
  archive=download(f'https://github.com/godotengine/godot-builds/releases/download/{GODOT}/Godot_v{GODOT}_linux.x86_64.zip',work/'godot.zip')
  if hashlib.sha256(archive.read_bytes()).hexdigest()!='cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4':raise RuntimeError('Reviewed Godot engine SHA256 differs')
  with zipfile.ZipFile(archive) as zipped:
   expected=f'Godot_v{GODOT}_linux.x86_64'
   if zipped.namelist()!=[expected]:raise RuntimeError('Unexpected official engine archive')
   engine=work/expected;engine.write_bytes(zipped.read(expected));engine.chmod(0o700)
  env=os.environ.copy();env['GENESIS_AI_MODEL']=str(model);env['LD_LIBRARY_PATH']=str(library.parent/'bin')
  subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-p','test_inference_bridge.py','-v'],cwd=ROOT,env=env,check=True,timeout=300)
  import shutil
  shutil.copyfile(library,ROOT/'native/genesis_ai.so');build_adapter(ROOT/'native')
  saved={name:os.environ.get(name) for name in ('GENESIS_AI_MODEL','LD_LIBRARY_PATH')}
  os.environ.update({name:env[name] for name in saved})
  try:
   run_game(engine,['--path',str(ROOT/'native'),'--editor','--import','--quit'],isolated=False)
   run_game(engine,['--path',str(ROOT/'native'),'--script','res://tests/inference_test.gd'],'GENESIS_NATIVE_AI_GENERATION_OK')
  finally:
   for name,value in saved.items():
    if value is None:os.environ.pop(name,None)
    else:os.environ[name]=value
  result={'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'platform':'linux-x64','modelSourceCommit':model_commit,'modelSha256':MODEL_SHA,'godotSourceCommit':GODOT_COMMIT,'actualCapiGenerationCancellationReuse':True,'actualGodotGeneration':True,'androidDeviceAcceptance':'UNRUN','publicationAuthorized':False}
  print('NATIVE_BRIDGE_REAL_MODEL_VERIFIED_JSON:'+json.dumps(result,sort_keys=True))

if __name__=='__main__':main()
