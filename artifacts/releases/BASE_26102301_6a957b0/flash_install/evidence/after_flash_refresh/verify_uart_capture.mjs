import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const B='D:/Codex/svflash921',O=B+'/after_flash_suite';
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const done=read(O+'/complete.json'),flash=read(B+'/flash_image.verified.json');
assert(done.accepted&&done.serial_tests_passed&&done.no_programming_during_suite);
assert.equal(done.bit_sha256,flash.bit_sha256);assert.equal(done.flash_image_sha256,flash.new_flash_sha256);
assert.equal(done.firmware,'26102301');assert.equal(done.cold_power_cycle_verified,false);
const xor=buffer=>[...buffer].reduce((x,b)=>x^b,0),summary={},healthValues=[];
let total=0;
for(const stage of ['ready','configuration','geometries','periods','recovery','monitor']){
 const folder=O+'/'+stage,events=fs.readFileSync(folder+'/trace.jsonl','utf8').replace(/^\uFEFF/,'').split(/\r?\n/).filter(Boolean).map(x=>JSON.parse(x));
 assert(!events.some(e=>['error','failure_restore_attempted','failure_restore_error'].includes(e.kind)),stage);
 assert.equal(events.at(-1).kind,'closed',stage);assert.equal(events.at(-1).exit_code,0,stage);
 const complete=events.filter(e=>e.kind==='complete');assert.equal(complete.length,1,stage);
 const rx=Buffer.concat(events.filter(e=>e.kind==='rx').map(e=>Buffer.from(e.hex,'hex')));
 assert(rx.equals(fs.readFileSync(folder+'/rx.bin')),stage);
 for(const e of events.filter(e=>e.kind==='rx'))assert.equal(Buffer.from(e.hex,'hex').toString('ascii'),e.text,stage);
 const tx=events.filter(e=>e.kind==='tx'),acks=events.filter(e=>e.kind==='ack');assert(tx.length>0);assert.equal(tx.length,acks.length,stage);
 const rawAcks=[...rx.toString('ascii').matchAll(/\$C:ACK=([0-9A-F]{2}),([0-9A-F]{8})\*([0-9A-F]{2})\r\n/g)].map(m=>m[0]);
 assert.deepEqual(rawAcks,acks.map(e=>e.frame+'\r\n'),stage);
 for(let i=0;i<tx.length;i++){
  const t=tx[i],a=acks[i];assert.equal(t.body,a.body,stage);
  const payload=Buffer.from(t.body,'ascii'),frame='$'+t.body+'*'+xor(payload).toString(16).toUpperCase().padStart(2,'0')+'\r\n';
  assert(Buffer.from(t.hex,'hex').equals(Buffer.from(frame,'ascii')),stage);
  const match=/^\$C:ACK=([0-9A-F]{2}),([0-9A-F]{8})\*([0-9A-F]{2})$/.exec(a.frame);assert(match,stage);
  assert.equal(xor(Buffer.from(a.frame.slice(1,a.frame.indexOf('*')),'ascii')),parseInt(match[3],16),stage);
  assert.equal(parseInt(match[1],16),0,stage);assert.equal(a.code,0,stage);assert.equal(parseInt(match[2],16),a.value,stage);
  if(t.body==='B:DIAG=0')assert.equal(a.value,0x26102301,stage);
 }
 const health=events.filter(e=>e.kind==='health').map(e=>e.values);healthValues.push(...health);
 for(const h of health){assert.equal(h.CACHE,15,stage);assert.equal(h.WAVFALLBACK,0,stage);for(const k of ['LEVEL','INTEGRITY','PRESENTATION','RECOVERY','VUNDERFLOW','UNDERFLOW','OVERFLOW','FAULT'])assert.equal(h[k],0,stage+':'+k);}
 summary[stage]={ack_frames:acks.length,receive_bytes:rx.length,health_checks:health.length,complete:complete[0],trace_sha256:sha(folder+'/trace.jsonl'),rx_sha256:sha(folder+'/rx.bin')};total+=acks.length;
 if(stage==='periods'){
  const rows=events.filter(e=>e.kind==='period_commit');assert.equal(rows.length,12);assert.deepEqual([...new Set(rows.map(e=>e.period))].sort((a,b)=>a-b),[2,5,10,30]);
  summary[stage].measured_intervals_ms=Object.fromEntries([2,5,10,30].map(p=>[p,rows.filter(e=>e.period===p&&e.index>0).map(e=>e.interval_ms)]));
 }
 if(stage==='recovery'){
  const identities=events.filter(e=>e.kind==='media_key_identity').map(e=>e.values);assert.equal(identities.length,3);assert.equal(new Set(identities.map(e=>e.IDLOW+':'+e.IDHIGH)).size,1);summary[stage].actual_slot_keys=identities[0].slot_keys;
 }
 if(stage==='monitor'){
  const observations=events.filter(e=>e.kind==='observation').map(e=>e.values);assert(observations.length);
  for(const h of observations){assert.equal(h.STATUS,7);assert.equal(h.CACHE,15);for(const k of ['LEVEL','INTEGRITY','PRESENTATION','VUNDERFLOW','UNDERFLOW','OVERFLOW','EVENTDROP','UARTREJECT','UARTFRAME','UARTOVERRUN','UARTDROP'])assert.equal(h[k],0,'monitor:'+k);}
  const c=events.filter(e=>e.kind==='carousel_complete');assert.equal(c.length,1);assert(c[0].validation.accepted);summary[stage].carousel=c[0].validation;
 }
}
assert.equal(summary.configuration.complete.configuration_cases,40);assert.equal(summary.geometries.complete.combinations,8);assert.equal(summary.geometries.complete.manual_fade_commits,32);assert.equal(summary.recovery.complete.recovery_cycles,2);
const result={accepted:true,utc:new Date().toISOString(),scope:'Independent byte and checksum validation of actual post-Flash refresh UART capture',firmware:done.firmware,source_commit:done.source_commit,bit_sha256:done.bit_sha256,raw_flash_sha256:flash.new_flash_sha256,total_validated_ack_frames:total,wav_fallback_masks:[...new Set(healthValues.map(h=>h.WAVFALLBACK))],stages:summary,reader_sha256:sha(import.meta.filename),flash_written:true,cold_power_cycle_verified:false,cold_test_deferred_by_user:true,physical_display_verified_this_cycle:false,physical_audio_verified_this_cycle:false,physical_spectrum_verified_this_cycle:false,github_uploaded:false};
assert(!fs.existsSync(B+'/uart_capture.verified.json'),'Preserve prior validation');fs.writeFileSync(B+'/uart_capture.verified.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify({...result,stages:undefined}));
