


from pathlib import Path
import argparse,hashlib,importlib,json,re,sys,xml.etree.ElementTree as ET

def exercise(folder):
    domains=importlib.import_module('check_v3_native_clock_domains')
    original=importlib.import_module('check_v3_native_clock_selftest')
    Native,check_texts,PLL,clean,net=domains.Native,domains.check_texts,domains.PLL,domains.clean,domains.net
    change_port,change_xml=original.change_port,original.change_xml
    folder=Path(folder)
    names=('gate.netlist.v','route.netlist.v','route.clocks');gate,route,xml=[(folder/n).read_text()for n in names]
    actual=check_texts(gate,route,xml,external_reset=True,sys_output=1);assert actual['accepted']and len(actual['physical_stages']['gate'])==60 and len(actual['physical_stages']['route'])==74
    r=Native(route);g=Native(gate);signal='reset_cache_write/release_pipe';rc,bit=r.ff_driver(signal+'[0]');rc1,bit1=r.ff_driver(signal+'[1]')
    assert rc['name']==rc1['name'] and bit==0 and bit1==1
    gc,_=g.ff_driver(signal+'[0]');packet='video/cache/packed_data$store/packet_data[0]';mem_r=r.ff_driver(packet)[0]['ports']['clk'];mem_g=g.ff_driver(packet)[0]['ports']['clk']
    assert net(rc['ports']['q'])==signal
    options=dict(external_reset=True,sys_output=1)
    replicas=r.reset_drivers('reset_sys/release_pipe[1]',route);assert len(replicas)==15
    clone_name,clone,clone_bit=replicas[0];assert clone_bit==0
    write_r=rc['ports']['clk']
    def move_XML_to_WRITE100(pin):
     tree=ET.fromstring(xml);parents={c:p for p in tree.iter()for c in p};hits=[x for x in tree.iter('pin')if x.get('name')==pin];assert len(hits)==1
     parents[hits[0]].remove(hits[0]);next(x for x in tree.iter('clock')if x.get('name')==PLL+'.clkc[0]').append(hits[0])
     return ET.tostring(tree,encoding='unicode')
    clone_mi=clone['ports']['mi'];assert clone_mi.count('\\reset_sys/release_pipe [0]')==1
    bare_declaration=re.compile(r'(^\s*wire\s*)\[1:0\](\s+\\reset_cache_write/release_pipe\s*;)',re.M)
    clean_route=clean(route);assert len(bare_declaration.findall(clean_route))==1
    match=bare_declaration.search(clean_route);missing_declaration=clean_route[:match.start()]+clean_route[match.end():]
    short_declaration=bare_declaration.sub(lambda m:m[1]+'[0:0]'+m[2],clean_route)
    cases=[
     ('real883_bare_bus',[gate,route,xml],False,'unchanged_actual_TD_capture'),
     ('equivalent_explicit_slice',[gate,change_port(route,rc['name'],'q','\\'+signal+' [1:0]'),xml],False,'equivalent_parser_control'),
     ('equivalent_explicit_concat',[gate,change_port(route,rc['name'],'q','{\\'+signal+' [1],\\'+signal+' [0]}'),xml],False,'equivalent_parser_control'),
     ('route_bus_bit1_lost',[gate,change_port(route,rc['name'],'q','\\'+signal+' [0]'),xml],True,'semantic_negative_control'),
     ('route_duplicate_Q_bit',[gate,change_port(route,rc['name'],'q','{\\'+signal+' [0],\\'+signal+' [0]}'),xml],True,'semantic_negative_control'),
     ('route_bus_declaration_missing',[gate,missing_declaration,xml],True,'semantic_negative_control'),
     ('route_bus_width_shrunk',[gate,short_declaration,xml],True,'semantic_negative_control'),
     ('route_reset_bus_wrong_MEM50_clock',[gate,change_port(route,rc['name'],'clk',mem_r),xml],True,'semantic_negative_control'),
     ('gate_reset_bit_wrong_MEM50_clock',[change_port(gate,gc['name'],'clk',mem_g),route,xml],True,'semantic_negative_control'),
     ('xml_reset_bus_wrong_owner',[gate,route,change_xml(xml,'wrong_owner',rc['name']+'.clk')],True,'semantic_negative_control'),
     ('xml_reset_bus_missing_endpoint',[gate,route,change_xml(xml,'missing_pin',rc['name']+'.clk')],True,'semantic_negative_control'),
     ('sys_clone_Q_missing',[gate,change_port(route,clone['name'],'q','{open_n112582,negative_control_missing_SYS_clone}'),xml],True,'semantic_negative_control'),
     ('sys_clone_wrong_WRITE100_clock',[gate,change_port(route,clone['name'],'clk',write_r),xml],True,'semantic_negative_control'),
     ('sys_clone_wrong_preceding_data',[gate,change_port(route,clone['name'],'mi',clone_mi.replace('\\reset_sys/release_pipe [0]',"1'b1")),xml],True,'semantic_negative_control'),
     ('sys_clone_wrong_async_reset',[gate,change_port(route,clone['name'],'sr',"1'b1"),xml],True,'semantic_negative_control'),
     ('sys_clone_wrong_XML_clock',[gate,route,move_XML_to_WRITE100(clone['name']+'.clk')],True,'semantic_negative_control'),
     ('sys_clone_XML_missing',[gate,route,change_xml(xml,'missing_pin',clone['name']+'.clk')],True,'semantic_negative_control')]
    rows=[]
    for label,inputs,reject,kind in cases:
     error=None
     try:check_texts(*inputs,**options)
     except (ValueError,ET.ParseError)as ex:error=str(ex)
     assert bool(error)==reject,(label,error)
     rows.append(dict(case=label,expected_reject=reject,rejected=bool(error),error=error,input_kind=kind))
    receipt=dict(complete=True,accepted=True,
     bare_bus_positive=3,bare_bus_and_SYS_clone_expected_rejections=14,results=rows,
     actual_native883_bindings=dict(gate=60,route=74),validated_SYS_stage1_replicas=15,actual_same_slice_independent_Q_bits=[bit,bit1],
     inputs={n:hashlib.sha256((folder/n).read_bytes()).hexdigest()for n in names},
     checker_sha256=hashlib.sha256(Path(domains.__file__).read_bytes()).hexdigest(),
     frozen206_modified=False,original_TD_reports_modified=False,routed_STA_or_bitgen_approved=False)

    return receipt

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--positive-folder',type=Path,required=True)
    parser.add_argument('--legacy-tools',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    sys.path.insert(0,str(args.repo/'safevision/tools'))
    if args.legacy_tools:sys.path.insert(1,str(args.legacy_tools))
    result=exercise(args.positive_folder)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print('PASS native barebus/15-SYS-clone parser:3 positive14 expected refusals')

if __name__=='__main__':main()
