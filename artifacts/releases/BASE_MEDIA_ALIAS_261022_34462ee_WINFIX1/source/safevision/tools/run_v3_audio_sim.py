"""Native XSim regression. Explicit manifests, isolated ASCII work, fail closed."""
import argparse,hashlib,json,os,re,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def run(argv,folder,log,env,timeout=600):
    with (folder/log).open('w',encoding='utf-8') as f:
        p=subprocess.run(argv,cwd=folder,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
    if p.returncode:raise RuntimeError(f'{argv[0]} exit={p.returncode}: {folder/log}')
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--suite',default='audio_v3')
    ap.add_argument('--xsim-bin',default='D:/Xilinx/Vivado/2018.3/bin')
    ap.add_argument('--run-dir',required=True);ap.add_argument('--top',action='append')
    ap.add_argument('--override-source',action='append',default=[],metavar='REPO_PATH=SCRATCH_FILE')
    a=ap.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_]+',a.suite):raise ValueError('invalid suite name')
    manifest=json.loads((ROOT/f'safevision/build/manifests/{a.suite}_sim.json').read_text(encoding='utf-8'))
    base=Path(a.run_dir).resolve()
    if not str(base).isascii():raise ValueError('XSim2018.3 requires ASCII output directory')
    base.mkdir(parents=True,exist_ok=True);(base/'tmp').mkdir(exist_ok=True)
    env=os.environ.copy();env['TEMP']=env['TMP']=str(base/'tmp')
    tools={k:Path(a.xsim_bin)/(k+'.bat') for k in ('xvlog','xelab','xsim')}
    overrides={}
    for item in a.override_source:
        name,path=item.split('=',1)
        if name not in manifest['sources']:raise ValueError('override not in source manifest: '+name)
        overrides[name]=Path(path).resolve()
        if not overrides[name].is_file():raise FileNotFoundError(path)
    results=[]
    for top in (a.top or manifest['tops']):
        if top not in manifest['tops']:raise ValueError(top)
        folder=base/top;folder.mkdir(exist_ok=True)
        generator=manifest.get('generators',{}).get(top)
        if generator:
            subprocess.run([sys.executable,str(ROOT/generator),'--output',str(folder)],check=True)
        for name in manifest.get('assets',[]):
            import shutil
            shutil.copyfile(ROOT/name,folder/Path(name).name)
        src=manifest['sources']+['safevision/verification/unit/'+top+'.sv']
        for f in src:
            if not (ROOT/f).is_file():raise FileNotFoundError(f)
        files={name:overrides.get(name,ROOT/name) for name in src}
        for p in (ROOT/'safevision/rtl/include').glob('*.vh'):files[p.relative_to(ROOT).as_posix()]=p
        for name in manifest.get('assets',[]):files[name]=ROOT/name
        if generator:files[generator]=ROOT/generator
        files['safevision/tools/gen_v3_audio_fixture.py']=ROOT/'safevision/tools/gen_v3_audio_fixture.py'
        files['safevision/tools/run_v3_audio_sim.py']=Path(__file__)
        files[f'safevision/build/manifests/{a.suite}_sim.json']=ROOT/f'safevision/build/manifests/{a.suite}_sim.json'
        def snapshot():return {name:hashlib.sha256(path.read_bytes()).hexdigest() for name,path in files.items()}
        before=snapshot()
        (folder/'sources.sha256.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
        (folder/'sources.prj').write_text('\n'.join('"'+files[f].as_posix()+'"' for f in src),encoding='utf-8')
        start=time.monotonic();entry={'top':top,'status':'FAIL','source_overrides':sorted(overrides)}
        try:
            defines=sum((['-d',d] for d in manifest.get('defines',['SIM_FAST_TO'])),[])
            run([str(tools['xvlog']),'--sv',*defines,'-i',str(ROOT/'safevision/rtl/include'),
                 '--file','sources.prj','--log','compile.log'],folder,'compile.console.log',env)
            run([str(tools['xelab']),'work.'+top,'-s',top,'--mt','off','--timescale','1ns/1ps',
                 '--log','elab.log'],folder,'elab.console.log',env)
            run([str(tools['xsim']),top,'-runall','--log','sim.log'],folder,'sim.console.log',env,
                manifest.get('timeouts',{}).get(top,600))
            text=(folder/'sim.log').read_text(encoding='utf-8',errors='replace')
            errors=re.findall(r'errors\s*=\s*(\d+)',text)
            checks=len(re.findall(r'\[PASS\]',text))
            marker=bool(re.search(r'PASS\s+'+re.escape(top)+r'\b|\[TB\]\s*'+re.escape(top)+r'\s+done',text))
            bad=bool(re.search(r'(?im)(\[FAIL\]|\[SKIP\]|^\s*(?:\[[^]\n]+\]\s*)?(?:FAIL\b|FATAL\b|Fatal:|ERROR:|SKIP\b))',text))
            if not marker or '$finish called' not in text or bad or not checks or not errors or any(int(x) for x in errors):
                raise RuntimeError('missing completion/checks or nonzero error: '+str(folder/'sim.log'))
            after=snapshot()
            (folder/'sources.after.sha256.json').write_text(json.dumps(after,indent=2),encoding='utf-8')
            if after!=before:raise RuntimeError('source changed during test; evidence invalid')
            entry.update(status='PASS',checks=checks)
            compared=re.findall(r'comparisons\s*=\s*(\d+)',text)
            if compared:entry['data_comparisons']=int(compared[-1])
        except Exception as ex:entry['error']=str(ex)
        entry['elapsed_s']=round(time.monotonic()-start,3);results.append(entry)
        print(json.dumps(entry),flush=True)
        (base/'results.json').write_text(json.dumps({'suite':a.suite,'results':results,'complete':False},indent=2),encoding='utf-8')
    complete=len(results)==len(a.top or manifest['tops']) and all(x['status']=='PASS' for x in results)
    (base/'results.json').write_text(json.dumps({'suite':a.suite,'results':results,'complete':complete,
      'hardware_verified':False,'encrypted_vendor_behavior_verified':False},indent=2),encoding='utf-8')
    return 0 if complete else 1
if __name__=='__main__':sys.exit(main())
