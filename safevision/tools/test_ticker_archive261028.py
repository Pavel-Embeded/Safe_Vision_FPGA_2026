"""Exercise archive restoration and refusal paths without touching project data."""
import json,tempfile,unittest,zipfile
from pathlib import Path
from ticker_evidence_archive import pack,unpack
class ArchiveControls(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='sv-ticker-archive-');self.root=Path(self.temp.name)
  self.source=self.root/'inputs';self.source.mkdir();(self.source/'a.log').write_bytes(b'original evidence\n');(self.source/'b.bin').write_bytes(b'original evidence\n')
  self.zip=self.root/'proof.zip';self.index=pack({'native':self.source},self.zip)
 def tearDown(self):self.temp.cleanup()
 def rewrite(self,change):
  with zipfile.ZipFile(self.zip)as z:data={name:z.read(name)for name in z.namelist()}
  change(data);changed=self.root/'changed.zip'
  with zipfile.ZipFile(changed,'w',zipfile.ZIP_DEFLATED)as z:
   for name,value in data.items():z.writestr(name,value)
  return changed
 def test_deduplicated_round_trip(self):
  self.assertEqual(self.index['objects'],1);unpack(self.zip,self.root/'restore')
  for name in('a.log','b.bin'):self.assertEqual((self.root/'restore/native'/name).read_bytes(),(self.source/name).read_bytes())
 def test_corrupted_data_refused(self):
  def corrupt(data):data[next(n for n in data if n.startswith('objects/'))]=b'corrupted'
  with self.assertRaisesRegex(ValueError,'corrupted'):unpack(self.rewrite(corrupt),self.root/'bad')
 def test_escaping_path_refused(self):
  def escape(data):
   m=json.loads(data['index.json']);m['entries']['../outside']=m['entries'].pop('native/a.log');data['index.json']=json.dumps(m).encode()
  with self.assertRaisesRegex(ValueError,'unsafe'):unpack(self.rewrite(escape),self.root/'bad')
 def test_unlisted_object_refused(self):
  with self.assertRaisesRegex(ValueError,'unlisted'):unpack(self.rewrite(lambda d:d.update({'objects/'+'0'*64:b'extra'})),self.root/'bad')
 def test_wrong_size_refused(self):
  def size(data):
   m=json.loads(data['index.json']);m['entries']['native/a.log']['bytes']+=1;m['logical_bytes']+=1;data['index.json']=json.dumps(m).encode()
  with self.assertRaisesRegex(ValueError,'byte count'):unpack(self.rewrite(size),self.root/'bad')
 def test_duplicate_member_refused(self):
  with zipfile.ZipFile(self.zip,'a')as z:z.writestr('index.json',json.dumps(self.index))
  with self.assertRaisesRegex(ValueError,'duplicate'):unpack(self.zip,self.root/'bad')
 def test_existing_destination_refused(self):
  p=self.root/'existing';p.mkdir()
  with self.assertRaisesRegex(ValueError,'fresh'):unpack(self.zip,p)
if __name__=='__main__':unittest.main()
