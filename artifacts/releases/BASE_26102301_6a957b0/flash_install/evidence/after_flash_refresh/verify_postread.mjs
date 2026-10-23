import fs from 'node:fs';import path from 'node:path';import crypto from 'node:crypto';
const B='D:/Codex/svflash921',D='D:/Safe_Vision_FPGA_2026/artifacts/flash_install/BASE_26102301_6a957b0';
function check(v,m){if(!v)throw Error(m)}
function bytes(p){return fs.readFileSync(p)}function sha(p){return crypto.createHash('sha256').update(bytes(p)).digest('hex')}
function text(p){const b=bytes(p);return (b[0]===255&&b[1]===254?b.subarray(2).toString('utf16le'):b.toString('utf8')).replace(/^\uFEFF/,'')}
const before=JSON.parse(text(B+'/backup.verified.json'));const prog=JSON.parse(text(B+'/programming.verified.json'));
check(prog.accepted&&prog.official_verify_spi_completed,'No native programming approval');
const a=B+'/programmed_flash_a.bin',b=B+'/programmed_flash_b.bin';
check(fs.statSync(a).size===2097152&&fs.statSync(b).size===2097152,'Incomplete full Flash read');
check(sha(a)===sha(b)&&sha(a)!==before.original_flash_sha256,'Full new Flash reads unequal or unchanged');
const log=text(B+'/read_after_refresh.console.log');
check(log.includes('FLASH921_POST_READ_DONE a')&&log.includes('FLASH921_POST_READ_DONE b')&&log.includes('FLASH921_REFRESH_DONE'),'Post read/reload not completed');
check(!/FLASH921_\w+_FAILED|PRG-\d+\s+ERROR|RUN-\d+\s+ERROR/i.test(log),'Post read/reload reported error');
check(log.includes('-mode refresh')&&!/-mode jtag\b/.test(log),'Reload must use Flash refresh, no SRAM download');
const E=D+'/evidence/flash_program';check(!fs.existsSync(E),'Preserve earlier archive');fs.mkdirSync(E,{recursive:true});const files={};
for(const n of ['preflight.json','backup.verified.json','programming.command.receipt.json','programming.verified.json','program_verify_flash.tcl','program_verify_flash.console.log','read_after_refresh.tcl','read_after_refresh.console.log','programmed_flash_a.bin','programmed_flash_b.bin']){fs.copyFileSync(B+'/'+n,E+'/'+n);check(sha(E+'/'+n)===sha(B+'/'+n),'Archive changed '+n);files[n]=sha(E+'/'+n)}
const r={accepted:true,checked_at_utc:new Date().toISOString(),firmware:'26102301',source_commit:'6a957b0365adbc8d8b4069319d29c9fb63680428',bit_sha256:prog.bit_sha256,jedec_id:'EF4015',capacity_bytes:2097152,old_flash_sha256:before.original_flash_sha256,new_flash_sha256:sha(a),two_full_new_reads_identical:true,official_program_and_verify_passed:true,flash_refresh_returned:true,archive_payload_sha256:files,flash_written:true,cold_power_cycle_verified:false,github_uploaded:false};
for(const p of[B+'/flash_image.verified.json',E+'/flash_image.verified.json']){check(!fs.existsSync(p),'Preserve prior result');fs.writeFileSync(p,JSON.stringify(r,null,2)+'\n')}
console.log(JSON.stringify(r));
