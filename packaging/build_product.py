#!/usr/bin/env python3
"""Build the current checkout's local arm64 app using pinned public inputs.

Build tool only. The resulting app runs the frozen helper, never this script,
pip, the build interpreter or a repository/system Python fallback.
"""
from __future__ import annotations

import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request


ROOT=Path(__file__).resolve().parents[1]
MAGIC={b"\xcf\xfa\xed\xfe",b"\xfe\xed\xfa\xcf",b"\xce\xfa\xed\xfe",b"\xfe\xed\xfa\xce",b"\xca\xfe\xba\xbe",b"\xbe\xba\xfe\xca"}
SYSTEM=("/System/Library/","/usr/lib/")
RESOURCE_BUNDLES=("KeyboardShortcuts_KeyboardShortcuts.bundle","FluidAudio_LuxTtsG2pResources.bundle","GRDB_GRDB.bundle")


def build_environment(work,parent):
    environment=parent.copy()
    for key in ("PYTHONPATH","PYTHONHOME","VIRTUAL_ENV","PIP_INDEX_URL","PIP_EXTRA_INDEX_URL","PIP_CONFIG_FILE"):
        environment.pop(key,None)
    environment.update(PIP_CONFIG_FILE=os.devnull,PYINSTALLER_CONFIG_DIR=str(work/"pyinstaller-cache"),MACOSX_DEPLOYMENT_TARGET="15.2",PYTHONDONTWRITEBYTECODE="1",
        XDG_CACHE_HOME=str(work/"cache"),HF_HUB_OFFLINE="1",TRANSFORMERS_OFFLINE="1",
        CLANG_MODULE_CACHE_PATH=str(work/"clang-cache"),SWIFTPM_MODULECACHE_OVERRIDE=str(work/"swift-module-cache"))
    return environment


def run(arguments,*,env=None,capture=False):
    return subprocess.run([str(value) for value in arguments],cwd=ROOT,env=env,check=True,text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def digest_file(path):
    with Path(path).open("rb") as handle:
        value=sha256()
        while data:=handle.read(1024*1024): value.update(data)
    return value.hexdigest()


def verify(path,size,digest):
    if path.stat().st_size!=size or digest_file(path)!=digest:
        raise ValueError("Pinned public build input verification failed")


def fetch(url,target,*,size,digest,offline):
    if not url.startswith("https://github.com/astral-sh/python-build-standalone/releases/download/20261021/"):
        raise ValueError("Unreviewed interpreter build source")
    if not target.exists():
        if offline: raise ValueError("The pinned build input is not cached")
        temporary=target.with_suffix(target.suffix+".partial")
        try:
            with urllib.request.urlopen(url,timeout=60) as source,temporary.open("wb") as destination:
                count=0
                while chunk:=source.read(1024*1024):
                    count+=len(chunk)
                    if count>size: raise ValueError("Public build input exceeded its bound")
                    destination.write(chunk)
            verify(temporary,size,digest);temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    verify(target,size,digest)


def extract_verified(archive,destination,*,size,digest):
    verify(archive,size,digest)
    # The fixed trusted archive still receives Python's traversal/link filter.
    with tarfile.open(archive) as package: package.extractall(destination,filter="data")


def lock_versions():
    versions={}
    for name in ("runtime","build"):
        for line in (ROOT/f"packaging/{name}-requirements.lock").read_text().splitlines():
            match=re.match(r"^([a-zA-Z0-9_.-]+)==([^\s\\]+)",line)
            if match:
                key=re.sub(r"[-_.]+","-",match[1]).lower()
                if key in versions and versions[key]!=match[2]: raise ValueError("Conflicting pinned build locks")
                versions[key]=match[2]
    return versions


def prepare(work,environment,offline):
    descriptor=json.loads((ROOT/"packaging/python-build.json").read_text())
    archive=work/"cpython-3.14.9-20261021-arm64.tar.gz"
    fetch(descriptor["url"],archive,size=descriptor["size"],digest=descriptor["sha256"],offline=offline)
    interpreter=work/"interpreter"
    if not interpreter.exists(): extract_verified(archive,interpreter,size=descriptor["size"],digest=descriptor["sha256"])
    python=interpreter/"python/bin/python3.14"
    check="import sys,platform,sqlite3;assert sys.version_info[:3]==(3,14,9) and platform.machine()=='arm64';d=sqlite3.connect(':memory:');d.execute('create table proof(value)');s=d.serialize();r=sqlite3.connect(':memory:');r.deserialize(s);assert r.execute('select count(*) from proof').fetchone()[0]==0"
    run([python,"-I","-c",check],env=environment)
    virtual=work/"venv"
    if not virtual.exists(): run([python,"-m","venv",virtual],env=environment)
    python=virtual/"bin/python"
    arguments=[python,"-m","pip","--isolated","install","--index-url","https://pypi.org/simple","--disable-pip-version-check","--require-hashes","--only-binary=:all:","--no-compile","--cache-dir",work/"pip-cache"]
    if offline: arguments += ["--no-index"]
    arguments += ["-r",ROOT/"packaging/runtime-requirements.lock","-r",ROOT/"packaging/build-requirements.lock"]
    run(arguments,env=environment)
    installed=json.loads(run([python,"-c","import importlib.metadata,json;print(json.dumps({d.metadata['Name'].lower().replace('_','-'):d.version for d in importlib.metadata.distributions()}))"],env=environment,capture=True))
    expected=lock_versions()
    if any(installed.get(name)!=version for name,version in expected.items()) or set(installed)-set(expected)-{"pip"}:
        raise ValueError("The generated build environment does not match the reviewed locks")
    return python,descriptor,expected


def component_notices(work,python,descriptor,environment,offline):
    archive=work/"cpython-3.14.9-20261021-full.tar.zst"
    fetch(descriptor["noticesUrl"],archive,size=descriptor["noticesSize"],digest=descriptor["noticesSha256"],offline=offline)
    output=work/"python-component-notices"
    # Run zstd extraction with the selected3.14 interpreter, not host tools.
    script="""from pathlib import Path
import sys,tarfile
root=Path(sys.argv[2]);root.mkdir(exist_ok=True)
with tarfile.open(sys.argv[1],'r|zst') as archive:
 for item in archive:
  if item.name=='python/PYTHON.json' or item.name.startswith('python/licenses/'):
   if not item.isfile(): continue
   relative=Path(item.name).relative_to('python')
   if '..' in relative.parts or item.size>4*1024*1024: raise ValueError('Invalid component notice')
   target=root/relative;target.parent.mkdir(parents=True,exist_ok=True)
   target.write_bytes(archive.extractfile(item).read())
"""
    run([python,"-I","-c",script,archive,output],env=environment)
    metadata=json.loads((output/"PYTHON.json").read_text())
    if metadata["python_version"]!="3.14.9" or metadata["target_triple"]!="aarch64-apple-darwin":
        raise ValueError("Mismatched interpreter component notices")
    return output


def load_commands(output):
    dependencies=[];rpaths=[];minimum=None;command=None
    for line in output.splitlines():
        line=line.strip()
        if line.startswith("cmd "): command=line.split()[1]
        elif command in {"LC_LOAD_DYLIB","LC_LOAD_WEAK_DYLIB","LC_REEXPORT_DYLIB","LC_LOAD_UPWARD_DYLIB"} and line.startswith("name "):
            dependencies.append(line[5:].split(" (offset ",1)[0])
        elif command=="LC_RPATH" and line.startswith("path "):
            rpaths.append(line[5:].split(" (offset ",1)[0])
        elif (command=="LC_BUILD_VERSION" and line.startswith("minos ")) or (command=="LC_VERSION_MIN_MACOSX" and line.startswith("version ")):
            minimum=tuple(map(int,line.split()[1].split(".")))
    return dependencies,rpaths,minimum


def macho_files(root):
    seen=set()
    for path in root.rglob("*"):
        canonical=path.resolve()
        if path.is_symlink() and not canonical.is_relative_to(root.resolve()):
            raise ValueError("Product symlink escapes its bundle")
        if not path.is_file(): continue
        stat=path.stat();identity=(stat.st_dev,stat.st_ino)
        if identity in seen: continue
        with path.open("rb") as handle: magic=handle.read(4)
        if magic in MAGIC: seen.add(identity);yield canonical


def executable_for(path,app):
    helper=app/"Contents/Helpers/RelayRuntime.app"
    return helper/"Contents/MacOS/relay-helper" if path.is_relative_to(helper) else app/"Contents/MacOS/relay-panel-session"


def expand_load(value,loader,executable):
    if value.startswith("@loader_path/"): return loader/value.removeprefix("@loader_path/")
    if value.startswith("@executable_path/"): return executable.parent/value.removeprefix("@executable_path/")
    if value.startswith("/"): return Path(value)
    return None


def audit_native(app):
    count=0
    for path in macho_files(app):
        count+=1
        if run(["lipo","-archs",path],capture=True).strip()!="arm64": raise ValueError("Non-arm64 code in product")
        dependencies,rpaths,minimum=load_commands(run(["otool","-l",path],capture=True))
        if minimum is None or (minimum+(0,0))[:2]>(15,2): raise ValueError("Unsupported embedded minimum macOS")
        if any(value.startswith("/") and not value.startswith(SYSTEM) for value in rpaths):
            raise ValueError("Build-machine rpath remains in product")
        executable=executable_for(path,app)
        for dependency in dependencies:
            if dependency.startswith(SYSTEM): continue
            if dependency.startswith("@rpath/"):
                candidates=[base/dependency.removeprefix("@rpath/") for value in rpaths
                            if (base:=expand_load(value,path.parent,executable)) is not None]
            else:
                value=expand_load(dependency,path.parent,executable);candidates=[] if value is None else [value]
            if not any(str(candidate).startswith(SYSTEM) or (candidate.exists() and candidate.resolve().is_relative_to(app.resolve())) for candidate in candidates):
                raise ValueError("Unresolved non-system native dependency: "+str(path.relative_to(app)))
    if count==0: raise ValueError("No native code in product")
    return count


def smoke(helper,python,environment):
    child=environment.copy();child["RELAY_TEST_BUNDLED_HELPER"]=str(helper)
    run([python,"-m","unittest","discover","-s","tests","-p","test_product_runtime_bundle.py","-v"],env=child)


def copy_native_resources(binary_directory,resources):
    for name in RESOURCE_BUNDLES: shutil.copytree(binary_directory/name,resources/name,symlinks=True)
    shutil.copy2(ROOT/"spikes/macos-panel/THIRD_PARTY_NOTICES.md",resources/"RelayNativeNotices.txt")


def assemble(work,helper,native_scratch,environment,output,configuration):
    arguments=["swift","build","--disable-sandbox","--disable-automatic-resolution","--configuration",configuration,"--jobs","2","--package-path",ROOT/"spikes/macos-panel","--scratch-path",native_scratch,"--cache-path",work/"swift-cache","--product","relay-panel-session"]
    run(arguments,env=environment)
    binary_directory=Path(run(arguments[:-2]+["--show-bin-path"],env=environment,capture=True).strip())
    expected=ROOT/"spikes/macos-panel/.build/Relay.app"
    if output!=expected and not output.is_relative_to(work): raise ValueError("Product output must remain in the generated build directories")
    if output.suffix!=".app": raise ValueError("Product output must be an app bundle")
    stage=work/"Relay.staging.app"
    if stage.exists(): shutil.rmtree(stage)
    (stage/"Contents/MacOS").mkdir(parents=True)
    (stage/"Contents/Helpers").mkdir();(stage/"Contents/Resources").mkdir();(stage/"Contents/Frameworks").mkdir()
    shutil.copy2(binary_directory/"relay-panel-session",stage/"Contents/MacOS/relay-panel-session")
    shutil.copy2(ROOT/"spikes/macos-panel/Packaging/Info.plist",stage/"Contents/Info.plist")
    shutil.copytree(helper,stage/"Contents/Helpers/RelayRuntime.app",symlinks=True)
    copy_native_resources(binary_directory,stage/"Contents/Resources")
    frameworks=binary_directory/"PackageFrameworks"
    if frameworks.exists(): shutil.copytree(frameworks,stage/"Contents/Frameworks",dirs_exist_ok=True,symlinks=True)
    native=stage/"Contents/MacOS/relay-panel-session"
    _,rpaths,_=load_commands(run(["otool","-l",native],capture=True))
    for value in rpaths:
        if value.startswith("/") and not value.startswith(SYSTEM): run(["install_name_tool","-delete_rpath",value,native])
    if "@executable_path/../Frameworks" not in rpaths: run(["install_name_tool","-add_rpath","@executable_path/../Frameworks",native])
    count=audit_native(stage)
    # Signing an app's main executable by path signs its entire enclosing app.
    # Seal those containers only after every other nested code object is ready.
    nested_apps=sorted(stage.rglob("*.app"),key=lambda path:len(path.parts),reverse=True)
    main_executables={native.resolve()}
    for nested in nested_apps:
        with (nested/"Contents/Info.plist").open("rb") as handle: information=plistlib.load(handle)
        main_executables.add((nested/"Contents/MacOS"/information["CFBundleExecutable"]).resolve())
    for path in macho_files(stage):
        if path not in main_executables: run(["codesign","--force","--sign","-",path])
    for framework in sorted(stage.rglob("*.framework"),key=lambda path:len(path.parts),reverse=True): run(["codesign","--force","--sign","-",framework])
    for nested in nested_apps: run(["codesign","--force","--sign","-",nested])
    run(["codesign","--force","--sign","-",stage]);run(["codesign","--verify","--deep","--strict",stage])
    output.parent.mkdir(parents=True,exist_ok=True)
    if output.exists():
        with (output/"Contents/Info.plist").open("rb") as handle: existing=plistlib.load(handle)
        if existing.get("CFBundleIdentifier")!="com.relay.session": raise ValueError("Refusing to replace an unrelated app")
        shutil.rmtree(output)
    shutil.move(stage,output)
    return count


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-root",type=Path,default=ROOT/".build/product-runtime")
    parser.add_argument("--native-scratch",type=Path)
    parser.add_argument("--output",type=Path,default=ROOT/"spikes/macos-panel/.build/Relay.app")
    parser.add_argument("--offline",action="store_true")
    parser.add_argument("--helper-only",action="store_true")
    parser.add_argument("--configuration",choices=["debug","release"],default=os.environ.get("RELAY_BUILD_CONFIGURATION","release"))
    args=parser.parse_args()
    if sys.version_info<(3,12): parser.error("The developer packaging tool requires Python3.12 or newer")
    work=args.work_root.resolve();work.mkdir(parents=True,exist_ok=True)
    environment=build_environment(work,os.environ)
    python,descriptor,versions=prepare(work,environment,args.offline)
    notices=component_notices(work,python,descriptor,environment,args.offline)
    dirty=bool(run(["git","status","--porcelain","--untracked-files=normal"],capture=True).strip())
    provenance={"sourceCommit":run(["git","rev-parse","HEAD"],capture=True).strip(),"sourceDirty":dirty,"pythonBuild":descriptor,"packages":versions,
                "relaySourceSHA256":{str(path.relative_to(ROOT)):digest_file(path) for path in sorted((ROOT/"relay_spike").glob("*.py"))},
                "runtimeLockSHA256":digest_file(ROOT/"packaging/runtime-requirements.lock"),"buildLockSHA256":digest_file(ROOT/"packaging/build-requirements.lock")}
    (work/"build-provenance.json").write_text(json.dumps(provenance,indent=2,sort_keys=True)+"\n")
    environment["PYINSTALLER_STRICT_BUNDLE_CODESIGN_ERROR"]="1"
    environment["RELAY_RUNTIME_BUILD_ROOT"]=str(work)
    run([python,"-m","PyInstaller","--noconfirm","--distpath",work/"dist","--workpath",work/"pyinstaller",ROOT/"packaging/relay-helper.spec"],env=environment)
    helper=work/"dist/RelayRuntime.app"
    smoke(helper/"Contents/MacOS/relay-helper",python,environment)
    if args.helper_only: print(helper);return
    count=assemble(work,helper,(args.native_scratch or work/"native").resolve(),environment,args.output.resolve(),args.configuration)
    smoke(args.output.resolve()/"Contents/Helpers/RelayRuntime.app/Contents/MacOS/relay-helper",python,environment)
    size=sum(path.stat().st_size for path in args.output.resolve().rglob("*") if path.is_file() and not path.is_symlink())
    print(json.dumps({"app":str(args.output.resolve()),"bytes":size,"nativeFilesAudited":count},sort_keys=True))


if __name__=="__main__":main()
