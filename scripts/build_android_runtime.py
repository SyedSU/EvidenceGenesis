"""Build the reviewed CPU-only Android runtime from a supplied clean checkout.

No downloads, model execution, signing, publication or device-acceptance claims.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess

from build_native import LLAMA, LLAMA_COMMIT
from build_save_adapter import ANDROID_NDK_VERSION, android_compiler

REQUIRED_LIBRARIES={'libllama.so','libggml.so','libggml-base.so','libggml-cpu.so','libc++_shared.so'}
SYSTEM_LIBRARIES={'libc.so','libm.so','libdl.so'}


def verify_source(source, expected_commit=LLAMA_COMMIT):
    source=Path(source).resolve()
    def git(*arguments):
        return subprocess.check_output(['git','-C',str(source),*arguments],text=True,stderr=subprocess.PIPE).strip()
    try:
        if git('rev-parse','HEAD')!=expected_commit:
            raise ValueError('Runtime source differs from reviewed commit')
        if git('status','--porcelain','--untracked-files=all'):
            raise ValueError('Runtime source checkout must be clean')
    except subprocess.CalledProcessError as error:
        raise ValueError('Runtime source checkout unavailable') from error
    return source


def elf_identity(path):
    data=Path(path).read_bytes()
    if len(data)<64 or data[:6]!=b'\x7fELF\x02\x01' or struct.unpack_from('<H',data,18)[0]!=183:
        raise ValueError('Expected Android AArch64 ELF64 library')
    if struct.unpack_from('<H',data,16)[0]!=3:
        raise ValueError('Expected a shared ELF library')
    phoff=struct.unpack_from('<Q',data,32)[0]
    ehsize,phsize,phcount=struct.unpack_from('<HHH',data,52)
    if data[6]!=1 or struct.unpack_from('<I',data,20)[0]!=1 or ehsize!=64 or phsize!=56 or not 0<phcount<=1024 or phoff<64 or phoff+phcount*phsize>len(data):
        raise ValueError('Invalid ELF program header table')
    loads=[];dynamic=[]
    for index in range(phcount):
        kind,flags,offset,address,_physical,size,memory,alignment=struct.unpack_from('<IIQQQQQQ',data,phoff+index*phsize)
        if offset+size>len(data):raise ValueError('ELF segment extends beyond file')
        if kind==1:
            if size>memory or alignment<16384 or alignment&(alignment-1) or offset%alignment!=address%alignment or flags&3==3:
                raise ValueError('Invalid or non16KiB-compatible ELF load segment')
            loads.append((offset,address,size,alignment))
        elif kind==2:dynamic.append((offset,size))
        elif kind==0x6474e551 and flags&1:raise ValueError('Executable ELF stack is not supported')
    if not loads or len(dynamic)!=1 or dynamic[0][1]%16:raise ValueError('ELF load/dynamic segments missing or invalid')
    entries=[];terminated=False
    offset,size=dynamic[0]
    for position in range(offset,offset+size,16):
        tag,value=struct.unpack_from('<qQ',data,position)
        if tag==0:terminated=True;break
        if tag in (15,29,22):raise ValueError('ELF runtime paths or text relocations are not supported')
        entries.append((tag,value))
    if not terminated:raise ValueError('ELF dynamic table is unterminated')
    def unique(tag):
        values=[value for kind,value in entries if kind==tag]
        if len(values)!=1:raise ValueError('ELF dynamic string metadata missing or ambiguous')
        return values[0]
    address=unique(5);length=unique(10);table=None
    for file_offset,virtual,file_size,_alignment in loads:
        if virtual<=address and address+length<=virtual+file_size:
            table=data[file_offset+address-virtual:file_offset+address-virtual+length];break
    if table is None or not table:raise ValueError('ELF dynamic strings are outside loaded bytes')
    def string(index):
        if index>=len(table):raise ValueError('Invalid ELF dynamic string offset')
        end=table.find(b'\0',index)
        if end<0:raise ValueError('Unterminated ELF dynamic string')
        try:return table[index:end].decode('ascii')
        except UnicodeDecodeError as error:raise ValueError('Non-ASCII ELF dependency identity') from error
    soname=string(unique(14))
    if soname!=Path(path).name:raise ValueError('ELF SONAME differs from packaged filename')
    needed=sorted(string(value) for kind,value in entries if kind==1)
    return {'path':Path(path).name,'size':len(data),'sha256':hashlib.sha256(data).hexdigest(),
            'soname':soname,'needed':needed,'minimumLoadAlignment':min(item[3] for item in loads)}


def verify_bundle(output):
    output=Path(output);bundle=output/'arm64-v8a'
    if {path.name for path in bundle.iterdir()}!=REQUIRED_LIBRARIES:
        raise ValueError('Android runtime requires exactly the five reviewed libraries')
    records=[]
    for path in sorted(bundle.iterdir()):
        if not path.is_file() or path.is_symlink():raise ValueError('Runtime libraries must be regular files')
        record=elf_identity(path)
        if not set(record['needed'])<=REQUIRED_LIBRARIES|SYSTEM_LIBRARIES:
            raise ValueError('Unexpected Android runtime dependency')
        records.append(record)
    for name in ('llama.cpp-LICENSE.txt','Android-NDK-NOTICE.txt'):
        path=output/'licenses'/name
        if not path.is_file() or path.is_symlink() or not path.read_bytes():raise ValueError('Required runtime notice missing')
    return records


def build_runtime(source,ndk,cmake,ninja,output,jobs=2):
    output=Path(output).resolve()
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError('Runtime output must be an empty directory; cache and package reuse is refused')
    source=verify_source(source)
    android_compiler(ndk)
    if jobs<1 or jobs>8:raise ValueError('Build jobs must be between1 and8')
    for executable,expected in [(cmake,'cmake version 3.31.6'),(ninja,'1.11.1.git.kitware.jobserver-1')]:
        version=subprocess.check_output([str(executable),'--version'],text=True).splitlines()[0]
        if version!=expected:raise ValueError('Reviewed build tool required: '+expected)
    if output.is_relative_to(source):raise ValueError('Build output must be outside reviewed source checkout')
    build=output/'cmake';bundle=output/'arm64-v8a';bundle.mkdir(parents=True,exist_ok=True)
    options={
        'CMAKE_MAKE_PROGRAM':str(Path(ninja).resolve()),
        'CMAKE_TOOLCHAIN_FILE':str(Path(ndk).resolve()/'build/cmake/android.toolchain.cmake'),
        'ANDROID_ABI':'arm64-v8a','ANDROID_PLATFORM':'android-26','ANDROID_STL':'c++_shared',
        'ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES':'ON','CMAKE_BUILD_TYPE':'Release',
        'LLAMA_BUILD_TESTS':'OFF','LLAMA_BUILD_EXAMPLES':'OFF','LLAMA_BUILD_SERVER':'OFF',
        'LLAMA_BUILD_COMMON':'OFF','LLAMA_BUILD_TOOLS':'OFF','LLAMA_BUILD_MTMD':'OFF',
        'LLAMA_OPENSSL':'OFF','GGML_OPENMP':'OFF','GGML_OPENMP_FETCH':'OFF',
        'GGML_LLAMAFILE':'OFF','GGML_NATIVE':'OFF','GGML_CPU_ARM_ARCH':'armv8-a',
        'GGML_CPU_KLEIDIAI':'OFF','GGML_BACKEND_DL':'OFF','BUILD_SHARED_LIBS':'ON',
        'GGML_RPC':'OFF','GGML_CUDA':'OFF','GGML_VULKAN':'OFF','GGML_OPENCL':'OFF',
        'GGML_METAL':'OFF','GGML_SYCL':'OFF','GGML_HIP':'OFF','GGML_BLAS':'OFF',
        'FETCHCONTENT_FULLY_DISCONNECTED':'ON',
    }
    subprocess.run([str(cmake),'-S',str(source),'-B',str(build),'-G','Ninja',
                    *['-D'+key+'='+value for key,value in options.items()]],check=True)
    subprocess.run([str(cmake),'--build',str(build),'--parallel',str(jobs),'--target','llama','ggml-cpu'],check=True)
    files=[]
    for name in ('libllama.so','libggml.so','libggml-base.so','libggml-cpu.so'):
        origin=build/'bin'/name
        record=elf_identity(origin);shutil.copyfile(origin,bundle/name);files.append(record)
    host='windows-x86_64' if os.name=='nt' else 'linux-x86_64'
    cpp=Path(ndk)/'toolchains/llvm/prebuilt'/host/'sysroot/usr/lib/aarch64-linux-android/libc++_shared.so'
    record=elf_identity(cpp);shutil.copyfile(cpp,bundle/cpp.name);files.append(record)
    notices=output/'licenses';notices.mkdir(exist_ok=True)
    shutil.copyfile(source/'LICENSE',notices/'llama.cpp-LICENSE.txt')
    # The selected NDK's complete notice accompanies its C++ runtime.
    shutil.copyfile(Path(ndk)/'NOTICE',notices/'Android-NDK-NOTICE.txt')
    files=verify_bundle(output)
    verify_source(source)
    report={'schema':1,'platform':'android-arm64','abi':'arm64-v8a','minimumApi':26,
            'runtime':{'version':LLAMA,'sourceCommit':LLAMA_COMMIT},'ndk':ANDROID_NDK_VERSION,
            'cmake':'3.31.6','ninja':'1.11.1.git.kitware.jobserver-1','options':options,'files':files,
            'deviceAcceptance':'unrun','localInferenceVerified':False,'publicationAuthorized':False}
    (output/'runtime-build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('source','ndk','cmake','ninja','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--jobs',type=int,default=2)
    args=parser.parse_args()
    print(json.dumps(build_runtime(args.source,args.ndk,args.cmake,args.ninja,args.output,args.jobs),indent=2))
