"""Build first-party CPU inference bridge from exact reviewed local sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import platform
from build_android_runtime import verify_source,elf_identity
from build_save_adapter import HEADER_SHA,ANDROID_NDK_VERSION,android_compiler

ROOT=Path(__file__).resolve().parents[1]

def build(source,output,cmake,ninja,ndk=None,jobs=2):
    if not sys.platform.startswith("linux") or platform.machine().lower() not in ("x86_64","amd64"):raise ValueError("Bridge build host must be Linux x64; Windows uses the existing HTTP transport")
    source=verify_source(source);output=Path(output).resolve()
    if output.exists() and any(output.iterdir()):raise ValueError('Bridge build output must be empty')
    if output.is_relative_to(source):raise ValueError('Build output must be outside reviewed source')
    if not 1<=jobs<=8:raise ValueError('Build jobs must be between1 and8')
    for executable,expected in [(cmake,'cmake version 3.31.6'),(ninja,'1.11.1.git.kitware.jobserver-1')]:
        if subprocess.check_output([str(executable),'--version'],text=True).splitlines()[0]!=expected:raise ValueError('Reviewed tool required: '+expected)
    header=ROOT/'native/durability/gdextension_interface.h'
    if hashlib.sha256(header.read_bytes()).hexdigest()!=HEADER_SHA:raise ValueError('Pinned Godot ABI header changed')
    options={'CMAKE_BUILD_TYPE':'Release','CMAKE_MAKE_PROGRAM':str(Path(ninja).resolve()),'GENESIS_LLAMA_SOURCE':str(source),'FETCHCONTENT_FULLY_DISCONNECTED':'ON'}
    if ndk:
        android_compiler(ndk)
        options.update({'CMAKE_TOOLCHAIN_FILE':str(Path(ndk).resolve()/'build/cmake/android.toolchain.cmake'),'ANDROID_ABI':'arm64-v8a','ANDROID_PLATFORM':'android-26','ANDROID_STL':'c++_shared','ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES':'ON'})
    subprocess.run([str(cmake),'-S',str(ROOT/'native/inference'),'-B',str(output),'-G','Ninja',*['-D'+k+'='+v for k,v in options.items()]],check=True)
    subprocess.run([str(cmake),'--build',str(output),'--parallel',str(jobs),'--target','genesis_ai'],check=True)
    library=output/'libgenesis_ai.so'
    if not library.is_file():raise ValueError('Linux/Android bridge shared library missing')
    records=[]
    if ndk:
        bundle=output/'arm64-v8a';bundle.mkdir()
        for name in ('libgenesis_ai.so','libllama.so','libggml.so','libggml-base.so','libggml-cpu.so'):
            original=library if name==library.name else output/'bin'/name
            shutil.copyfile(original,bundle/name);records.append(elf_identity(bundle/name))
        cpp=Path(ndk)/'toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so'
        shutil.copyfile(cpp,bundle/cpp.name);records.append(elf_identity(bundle/cpp.name))
        names={r['path'] for r in records}
        for record in records:
            if not set(record['needed'])<=names|{'libc.so','libm.so','libdl.so'}:raise ValueError('Unexpected bridge dependency')
    else:records=[{'path':library.name,'size':library.stat().st_size,'sha256':hashlib.sha256(library.read_bytes()).hexdigest()}]
    notices=output/'licenses';notices.mkdir()
    shutil.copyfile(source/'LICENSE',notices/'llama.cpp-LICENSE.txt')
    shutil.copyfile(ROOT/'native/durability/Godot-LICENSE.txt',notices/'Godot-LICENSE.txt')
    if ndk:shutil.copyfile(Path(ndk)/'NOTICE',notices/'Android-NDK-NOTICE.txt')
    verify_source(source)
    source_files={str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in [ROOT/'native/inference/inference_core.cpp',ROOT/'native/inference/inference_core.h',ROOT/'native/inference/inference_extension.c',ROOT/'native/inference/CMakeLists.txt',ROOT/'native/inference.gdextension']}
    report={'sourceFiles':source_files,'schema':1,'platform':'android-arm64' if ndk else 'linux-x64','runtimeSource':str(source),'runtimeCommit':subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip(),'ndk':ANDROID_NDK_VERSION if ndk else None,'files':records,'deviceAcceptance':'unrun','localInferenceVerified':False,'publicationAuthorized':False,'options':options}
    (output/'bridge-build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source','output','cmake','ninja'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--ndk',type=Path);parser.add_argument('--jobs',type=int,default=2)
    args=parser.parse_args();print(json.dumps(build(args.source,args.output,args.cmake,args.ninja,args.ndk,args.jobs),indent=2))
