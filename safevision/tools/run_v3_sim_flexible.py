"""Native FLEX-only XSim runner with immutable generator/runtime input receipts.

Historical run_v3_sim.py remains byte-for-byte unchanged. This runner requires
the explicit strict manifest flag, snapshots all original inputs before and
after generation, and captures copied/generated runtime assets before and after
native compilation/execution. An integrity failure is never an HDL detection.
"""
import argparse,hashlib,json,os,re,shutil,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
RUNNER='safevision/tools/run_v3_sim_flexible.py'
def require(ok,message):
    if not ok:raise ValueError(message)
def save(path,value):path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def inside(root,name):
    require(isinstance(name,str)and name and not Path(name).is_absolute(),'invalid relative input path: '+str(name))
    path=(root/name).resolve();require(path.is_relative_to(root.resolve()),'input path escapes declared folder: '+name)
    require(path.is_file(),'declared input missing: '+str(path));return path
def run(argv,folder,log,env,timeout=600):
    with(folder/log).open('w',encoding='utf-8')as f:
        process=subprocess.run(argv,cwd=folder,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
    if process.returncode:raise RuntimeError(f'{argv[0]} exit={process.returncode}: {folder/log}')
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--suite',required=True)
    ap.add_argument('--xsim-bin',default='D:/Xilinx/Vivado/2018.3/bin')
    ap.add_argument('--run-dir',required=True);ap.add_argument('--top',action='append')
    ap.add_argument('--override-source',action='append',default=[],metavar='REPO_PATH=SCRATCH_FILE')
    args=ap.parse_args();require(re.fullmatch(r'[A-Za-z0-9_]+',args.suite),'invalid suite name')
    manifest_name=f'safevision/build/manifests/{args.suite}_sim.json'
    manifest_path=inside(ROOT,manifest_name);manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    require(manifest.get('strict_generated_inputs')==1,'FLEX runner requires strict_generated_inputs=1')
    require(manifest.get('native_runner')==RUNNER,'manifest does not select strict FLEX runner')
    for key in ('sources','generator_dependencies','generated_assets'):
        require(isinstance(manifest.get(key),list),'strict manifest requires explicit '+key)
        require(len(manifest[key])==len(set(manifest[key])),'duplicate '+key+' declaration')
    base=Path(args.run_dir).resolve();require(str(base).isascii(),'XSim2018.3 requires ASCII output directory')
    base.mkdir(parents=True,exist_ok=True);(base/'tmp').mkdir(exist_ok=True)
    env=os.environ.copy();env['TEMP']=env['TMP']=str(base/'tmp');env['PYTHONDONTWRITEBYTECODE']='1'
    tools={name:Path(args.xsim_bin)/(name+'.bat')for name in ('xvlog','xelab','xsim')}
    overrides={}
    for item in args.override_source:
        name,path=item.split('=',1);require(name in manifest['sources'],'override not in explicit source manifest: '+name)
        require(name not in overrides,'duplicate source override: '+name);overrides[name]=Path(path).resolve()
        require(overrides[name].is_file(),'override file missing: '+path)
    selected=args.top or manifest['tops'];require(len(selected)==len(set(selected)),'duplicate selected top')
    results=[]
    for top in selected:
        require(top in manifest['tops'],'top not selected by manifest: '+top)
        folder=base/top;folder.mkdir(exist_ok=False);start=time.monotonic()
        entry=dict(top=top,status='FAIL',source_overrides=sorted(overrides),strict_generated_inputs=1,native_runner=RUNNER)
        files={};before=None
        try:
            tests=manifest.get('test_sources',{}).get(top,['safevision/verification/unit/'+top+'.sv'])
            if isinstance(tests,str):tests=[tests]
            src=list(dict.fromkeys(manifest['sources']+tests))
            files={name:overrides.get(name,inside(ROOT,name))for name in src}
            for path in(ROOT/'safevision/rtl/include').glob('*.vh'):files[path.relative_to(ROOT).as_posix()]=path
            for name in manifest.get('assets',[]):files[name]=inside(ROOT,name)
            generator=manifest.get('generators',{}).get(top)
            if generator:files[generator]=inside(ROOT,generator)
            require(generator or not manifest['generated_assets'],'runtime generated assets require a declared generator')
            for name in manifest['generator_dependencies']:files[name]=inside(ROOT,name)
            files[RUNNER]=Path(__file__).resolve();files[manifest_name]=manifest_path
            generation_before={name:sha(path)for name,path in files.items()}
            save(folder/'generation.before.sha256.json',generation_before)
            copied={Path(name).name:name for name in manifest.get('assets',[])}
            require(len(copied)==len(manifest.get('assets',[])),'copied runtime asset basenames collide')
            require(not(set(copied)&set(manifest['generated_assets'])),'static and generated runtime assets collide')
            for destination,name in copied.items():shutil.copyfile(files[name],folder/destination)
            if generator:
                run([sys.executable,'-X','utf8','-B',str(files[generator]),'--output',str(folder)],folder,'generation.console.log',env)
            generation_after={name:sha(path)for name,path in files.items()}
            save(folder/'generation.after.sha256.json',generation_after)
            require(generation_before==generation_after,'original source/generator/dependency changed during generation')
            for name in list(manifest['generated_assets'])+list(copied):files['generated:'+name]=inside(folder,name)
            def snapshot():return {name:sha(path)for name,path in files.items()}
            before=snapshot();save(folder/'sources.sha256.json',before)
            (folder/'sources.prj').write_text('\n'.join('"'+files[name].as_posix()+'"'for name in src),encoding='utf-8')
            defines=sum((['-d',value]for value in manifest.get('defines',['SIM_FAST_TO'])),[])
            run([str(tools['xvlog']),'--sv',*defines,'-i',str(ROOT/'safevision/rtl/include'),'--file','sources.prj','--log','compile.log'],folder,'compile.console.log',env)
            run([str(tools['xelab']),'work.'+top,'-s',top,'--mt','off','--timescale','1ns/1ps','--log','elab.log'],folder,'elab.console.log',env)
            run([str(tools['xsim']),top,'-runall','--log','sim.log'],folder,'sim.console.log',env,manifest.get('timeouts',{}).get(top,600))
            text=(folder/'sim.log').read_text(encoding='utf-8',errors='replace')
            errors=re.findall(r'errors\s*=\s*(\d+)',text);checks=len(re.findall(r'\[PASS\]',text))
            marker=bool(re.search(r'PASS\s+'+re.escape(top)+r'\b|\[TB\]\s*'+re.escape(top)+r'\s+done',text))
            bad=bool(re.search(r'(?im)(\[FAIL\]|\[SKIP\]|^\s*(?:\[[^]\n]+\]\s*)?(?:FAIL\b|FATAL\b|Fatal:|ERROR:|SKIP\b))',text))
            require(marker and '$finish called'in text and not bad and checks and errors and not any(int(value)for value in errors),'missing completion/checks or nonzero HDL error: '+str(folder/'sim.log'))
            entry.update(status='PASS',checks=checks)
            compared=re.findall(r'comparisons\s*=\s*(\d+)',text)
            if compared:entry['data_comparisons']=int(compared[-1])
        except Exception as error:entry['error']=str(error)
        finally:
            if before is not None:
                try:
                    after={name:sha(path)for name,path in files.items()};save(folder/'sources.after.sha256.json',after)
                    require(after==before,'source or copied/generated runtime asset changed during native test')
                except Exception as error:entry.update(status='FAIL',error=str(error))
        entry['elapsed_s']=round(time.monotonic()-start,3);results.append(entry);print(json.dumps(entry),flush=True)
        save(base/'results.json',dict(suite=args.suite,results=results,complete=False))
    complete=len(results)==len(selected)and all(row['status']=='PASS'for row in results)
    save(base/'results.json',dict(suite=args.suite,results=results,complete=complete,strict_generated_inputs=1,native_runner=RUNNER,hardware_verified=False,encrypted_vendor_behavior_verified=False))
    return 0 if complete else 1
if __name__=='__main__':sys.exit(main())
