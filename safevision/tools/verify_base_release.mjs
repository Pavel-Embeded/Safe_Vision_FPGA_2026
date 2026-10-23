// Read-only delivery validation. This does not rerun HDL, STA, or hardware tests.
import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const R=path.join(root,'artifacts/releases/BASE_26102301_6a957b0');
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
function checkMap(base,map){let n=0;for(const [rel,h]of Object.entries(map)){
 const p=path.resolve(base,rel),real=fs.realpathSync(p),prefix=path.resolve(base).toLowerCase()+path.sep;
 if(!p.toLowerCase().startsWith(prefix)||real.toLowerCase()!==p.toLowerCase())throw Error('Unsafe manifest path: '+rel);
 if(sha(p)!==h)throw Error('SHA256 mismatch: '+rel);n++;
}return n;}
const index=read(path.join(R,'release.index.json'));
if(index.firmware!=='26102301'||index.mode!=='BASE'||index.bit_sha256!=='95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e'||index.approval_source_commit!=='6a957b0365adbc8d8b4069319d29c9fb63680428')throw Error('Wrong release identity');
if(index.cold_power_cycle_verified||!index.flash_written||!index.flash_reload_uart_suite_passed||index.publication_changes_rtl)throw Error('Unexpected acceptance boundary');
const payload=checkMap(R,index.payload_sha256),inputs=checkMap(root,index.native_inputs_sha256);
if(inputs!==206||sha(path.join(R,index.bitstream))!==index.bit_sha256)throw Error('Wrong native input/bit identity');
const q=read(path.join(R,'qualification_summary.json')),uart=read(path.join(R,'flash_install/evidence/after_flash_refresh/uart_capture.verified.json'));
if(!q.accepted||q.positive_unique_tops!==303||q.negative_controls!==221||!uart.accepted||uart.total_validated_ack_frames!==5016||uart.wav_fallback_masks.some(v=>v!==0))throw Error('Missing existing acceptance evidence');
const walk=d=>fs.readdirSync(d,{withFileTypes:true}).flatMap(e=>{const p=path.join(d,e.name);if(e.isSymbolicLink())throw Error('Unexpected payload reparse');return e.isDirectory()?walk(p):[path.relative(R,p).replaceAll('\\','/')];});
const actual=walk(R).filter(n=>n!=='release.index.json').sort(),expected=Object.keys(index.payload_sha256).sort();if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error('Unexpected or missing release files');
console.log(JSON.stringify({accepted:true,firmware:index.firmware,bit_sha256:index.bit_sha256,approval_source_commit:index.approval_source_commit,source_inputs_verified:inputs,payload_files_verified:payload,existing_post_flash_ack_frames:5016,scope:'Read-only byte verification; no new HDL/STA/hardware test',cold_power_cycle_verified:false},null,2));
