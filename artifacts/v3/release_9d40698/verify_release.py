"""Verify an approved SafeVision release without writing to the design."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parent
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
index=read(ROOT/'release.index.json')
for name,digest in index['payload_sha256'].items():
 p=(ROOT/name).resolve();assert p.is_relative_to(ROOT.resolve()) and p.is_file() and sha(p)==digest,name
source=ROOT/'source' if (ROOT/'source').is_dir() else ROOT.parents[2]
sys.path.insert(0,str(source/'safevision/tools'))
from v3_functional_release import acceptance
from check_board_timing import assess,read_report
from check_v3_rom_netlist import check_roms
from v3_resource_policy import load
from check_v3_board import resource_gate
functional,proof=acceptance(source);assert functional['positive_native_tests']==113 and functional['strict_normal_ending_mutants']==28
for mode in ['base','hd']:
 row=index['modes'][mode];folder=ROOT/'native'/mode;m=read(folder/'build.manifest.json');gate=read(folder/'timing.gate.json')
 assert m['status']=='PASS' and m['source_commit']==index['source_commit'] and m['source_commit_binding']['verified'] and m['bit_generated'] and gate['gate_accepted']
 for name,digest in m['sources'].items():assert sha(source/name)==digest,('compiled/proof source drift',name)
 sta=assess(read_report(folder/'route.timing'),read_report(folder/'route.check'));assert sta['gate_accepted']
 assert resource_gate(read_report(folder/'route.area'),load(source))['accepted']
 assert sum(r['bytes_compared'] for r in check_roms(read_report(folder/'gate.netlist.v'),source))==3072
 assert sha(ROOT/row['bitstream'])==row['bit_sha256']==m['bitstream']['sha256']
print('PASS: exact payload, source/proof bytes,113 positives,28 semantic mutants, both native corners, resources,3072 ROM bytes and both bitstreams')
print('Physical hardware acceptance remains pending.')
