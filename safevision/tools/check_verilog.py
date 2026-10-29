import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from verilog_tokens import tokens

ROOT=Path(__file__).resolve().parents[2]
FORBIDDEN=set('logic bit byte shortint longint int typedef struct union enum interface modport package import class virtual always_comb always_ff always_latch unique priority foreach ref string timeunit timeprecision final join_any join_none'.split())
SYSTEM_EXTENSIONS={'$fatal','$error','$warning','$info','$urandom','$urandom_range','$isunknown','$bits','$size','$sformatf','$cast','$countones','$onehot','$onehot0','$past','$rose','$fell','$stable'}
UPDATES={'++','--','+=','-=','*=','/=','%=','&=','|=','^=','<<=','>>='}

def paths(root):
    run=subprocess.run(['git','-C',str(root),'rev-parse','--show-toplevel'],capture_output=True)
    if run.returncode==0 and Path(run.stdout.decode('utf-8').strip()).resolve()==root.resolve():
        result=subprocess.run(['git','-C',str(root),'ls-files','-z'],capture_output=True,check=True)
        return [root/name for name in result.stdout.decode('utf-8').split('\0')if name]
    return [p for p in root.rglob('*')if p.is_file()and '.git'not in p.parts and '__pycache__'not in p.parts]

def language(root=ROOT):
    all_files=paths(root)
    forbidden=[p.relative_to(root).as_posix()for p in all_files if p.suffix.lower()in('.sv','.svh','.vhd','.vhdl')]
    if forbidden:raise ValueError('HDL extension outside Verilog profile: '+str(forbidden))
    hdl=[p for p in all_files if p.suffix in('.v','.vh')]
    protected=[]
    dependency=json.loads((root/'safevision/platform/anlogic_eg4s20_hx4s20c/ip/protected_sources.sha256.json').read_text('utf-8-sig'))
    expected={(root/e['path']).resolve():e['sha256']for e in dependency}
    for path in hdl:
        ts=tokens(path.read_bytes().decode('utf-8-sig'))
        for i,t in enumerate(ts):
            if t.kind=='opaque':
                digest=hashlib.sha256(path.read_bytes()).hexdigest()
                if expected.get(path.resolve())!=digest:raise ValueError('protected vendor source checksum differs: '+str(path))
                protected.append(path.relative_to(root).as_posix())
            if t.kind=='identifier'and(t.text in FORBIDDEN or t.text in SYSTEM_EXTENSIONS)or t.text in UPDATES:
                raise ValueError('HDL outside Verilog-2005 profile: '+path.relative_to(root).as_posix()+': '+t.text)
            if t.text=="'"and i+1<len(ts)and ts[i+1].text in('(','{'):
                raise ValueError('HDL cast/aggregate outside Verilog-2005: '+str(path))
    return {'accepted':True,'standard':'IEEE 1364-2005','hdl_files':len(hdl),'readable_hdl_files':len(hdl)-len(protected),'protected_vendor_files':protected}

def run_compile(root,output,iverilog,jobs,elaborate=False):
    files=paths(root)
    hdl=[p for p in files if p.suffix in('.v','.vh')]
    dummy=output/'dummy.v';dummy.write_text('module v_parse_dummy; endmodule\n',encoding='ascii')
    work=[]
    for number,path in enumerate(hdl):
        if b'`pragma protect begin_protected'in path.read_bytes():continue
        folder=output/'files'/str(number);folder.mkdir(parents=True)
        source=path
        if path.suffix=='.vh':
            source=folder/'header.v';source.write_text('module v_header_parse;\n`include "'+path.name+'"\nendmodule\n',encoding='ascii')
        args=[iverilog,'-g2005','-tnull','-i','-s','v_parse_dummy','-I',str(root/'safevision/rtl/include'),'-I',str(path.parent),str(dummy),str(source)]
        work.append((path.relative_to(root).as_posix(),folder,args))
    def invoke(item):
        name,folder,args=item
        try:
            run=subprocess.run(args,cwd=folder,capture_output=True,timeout=180)
            text=(run.stdout+run.stderr).decode('utf-8',errors='replace')
            (folder/'compile.log').write_text(text,encoding='utf-8')
            return {'name':name,'accepted':run.returncode==0,'exit':run.returncode}
        except Exception as error:return {'name':name,'accepted':False,'error':str(error)}
    with ThreadPoolExecutor(max_workers=jobs)as pool:results=list(pool.map(invoke,work))
    elaborated=[]
    if elaborate:
        manifests=[p for p in files if p.parent==root/'safevision/build/manifests'and p.name.endswith('_sim.json')]
        work=[]
        for path in manifests:
            data=json.loads(path.read_text('utf-8-sig'));folder=output/'manifests'/path.stem;folder.mkdir(parents=True)
            tests=[]
            for top in data['tops']:
                names=data.get('test_sources',{}).get(top,['safevision/verification/unit/'+top+'.v'])
                tests+=([names]if isinstance(names,str)else names)
            sources=list(dict.fromkeys(data['sources']+tests))
            args=[iverilog,'-g2005','-tnull','-I',str(root/'safevision/rtl/include')]
            for parent in sorted({(root/n).parent for n in sources}):args+=['-I',str(parent)]
            for define in data.get('defines',['SIM_FAST_TO']):args+=['-D',define]
            for top in data['tops']:args+=['-s',top]
            args+=[str(root/name)for name in sources]
            work.append((path.stem,folder,args))
        with ThreadPoolExecutor(max_workers=jobs)as pool:elaborated=list(pool.map(invoke,work))
    return {'accepted':all(r['accepted']for r in results+elaborated),'syntax_files':results,'elaboration_manifests':elaborated}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--compile',action='store_true')
    parser.add_argument('--elaborate',action='store_true')
    parser.add_argument('--run-dir',type=Path)
    parser.add_argument('--iverilog',default='iverilog')
    parser.add_argument('--jobs',type=int,default=4)
    args=parser.parse_args()
    result=language()
    if args.compile or args.elaborate:
        if args.run_dir is None:parser.error('--run-dir is required')
        out=args.run_dir.resolve()
        if out.exists()or out.is_relative_to(ROOT):raise ValueError('fresh output outside repository required')
        out.mkdir(parents=True)
        executable=shutil.which(args.iverilog)
        if executable is None:raise FileNotFoundError(args.iverilog)
        result.update(run_compile(ROOT,out,executable,args.jobs,args.elaborate))
        (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items()if k not in('syntax_files','elaboration_manifests')}))
    return 0 if result['accepted']else 1

if __name__=='__main__':raise SystemExit(main())
