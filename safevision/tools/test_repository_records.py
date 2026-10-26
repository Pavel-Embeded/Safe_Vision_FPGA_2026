"""Exercise archive restoration and acceptance boundaries with isolated files."""
from pathlib import Path
import contextlib, io, json, shutil, sys, tempfile, unittest
from unittest.mock import patch
from audit_repository_records import ROOT, audit_acceptance, read, safe_path
import restore_debug_records as restore

class RecordsBoundary(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='safevision-records-')
        self.base = Path(self.tmp.name)
        self.repo = self.base/'repo'
        index = read(ROOT/'evidence/debug_history/index.json')
        self.group = 'artifacts/diagnostics/m50p8_trace_26101701'
        archive = next(a for a in index['archives'] if a['group'] == self.group)
        self.rows = [r for r in index['records'] if r['archive'] == archive['path']]
        self.archive = self.repo/archive['path']
        self.archive.parent.mkdir(parents=True)
        shutil.copy2(ROOT/archive['path'], self.archive)
        self.index_path = self.repo/'evidence/debug_history/index.json'
        self.index_path.write_text(json.dumps(dict(archives=[archive],records=self.rows)), encoding='utf-8')
        self.output = self.base/'output'

    def tearDown(self):
        self.tmp.cleanup()

    def run_restore(self, apply=False):
        args = ['restore_debug_records.py','--group',self.group,'--output',str(self.output)]
        if apply:
            args.append('--apply')
        with patch.object(restore, 'ROOT', self.repo), patch.object(sys, 'argv', args), contextlib.redirect_stdout(io.StringIO()):
            restore.main()

    def test_dry_run_does_not_create_output(self):
        self.run_restore()
        self.assertFalse(self.output.exists())

    def test_restore_matches_every_original_digest(self):
        self.run_restore(True)
        for row in self.rows:
            data = (self.output/row['member']).read_bytes()
            self.assertEqual(len(data), row['bytes'])
            self.assertEqual(restore.digest(data), row['sha256'])

    def test_corrupted_archive_rejected_before_output(self):
        data=bytearray(self.archive.read_bytes());data[len(data)//2]^=1;self.archive.write_bytes(data)
        with self.assertRaisesRegex(ValueError,'Archive checksum'):
            self.run_restore(True)
        self.assertFalse(self.output.exists())

    def test_escaping_member_rejected_before_output(self):
        d=read(self.index_path);d['records'][0]['member']='../outside';self.index_path.write_text(json.dumps(d))
        with self.assertRaisesRegex(ValueError,'Escaping'):
            self.run_restore(True)
        self.assertFalse((self.base/'outside').exists())

    def test_existing_output_not_overwritten(self):
        self.output.mkdir();p=self.output/'keep';p.write_bytes(b'keep')
        with self.assertRaisesRegex(ValueError,'empty'):
            self.run_restore(True)
        self.assertEqual(p.read_bytes(),b'keep')

    def test_normal_path_alias_can_be_canonicalized(self):
        original = Path.resolve
        alias = self.base/'SHORT~1'/'output'
        def resolving(path, *args, **kwargs):
            return self.output if path == alias else original(path, *args, **kwargs)
        with patch.object(Path, 'resolve', resolving):
            self.assertEqual(restore.output_directory(alias), self.output)

    def test_output_link_parent_is_rejected(self):
        original = Path.is_symlink
        def linked(path):
            return path == self.output.parent or original(path)
        with patch.object(Path, 'is_symlink', linked):
            with self.assertRaisesRegex(ValueError, 'through a link'):
                restore.output_directory(self.output)

    def test_absolute_and_windows_escape_paths(self):
        for name in ['../outside','/absolute','C:/drive',r'safe\..\outside']:
            with self.assertRaises(ValueError,msg=name):
                safe_path(self.repo,name)

    def test_duplicate_payload_restores_from_retained_bytes(self):
        manifest=read(ROOT/'evidence/repository_cleanup_261026/duplicates.json')
        row=next(r for r in manifest['records'] if 0 < r['bytes'] < 1024)
        data=(ROOT/row['retained']).read_bytes()
        source=self.repo/row['retained'];source.parent.mkdir(parents=True,exist_ok=True);source.write_bytes(data)
        p=self.repo/'evidence/repository_cleanup_261026/duplicates.json';p.parent.mkdir(parents=True,exist_ok=True)
        p.write_text(json.dumps(dict(records=[row])),encoding='utf-8')
        args=['restore_debug_records.py','--duplicates','--output',str(self.output),'--apply']
        with patch.object(restore,'ROOT',self.repo),patch.object(sys,'argv',args),contextlib.redirect_stdout(io.StringIO()):
            restore.main()
        self.assertEqual((self.output/row['removed']).read_bytes(),data)

    def test_user_feedback_cannot_become_machine_measurements(self):
        paths=['evidence/board/acceptance_updates.json','evidence/board/cold_boot_261025_user_report.json',
               'artifacts/releases/BASE_26102301_6a957b0/release.index.json']
        for name in paths:
            p=self.repo/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/name,p)
        audit_acceptance(self.repo)
        report=self.repo/paths[1];d=read(report);d['machine_verified']=True;report.write_text(json.dumps(d))
        with self.assertRaisesRegex(ValueError,'promoted'):
            audit_acceptance(self.repo)
        d['machine_verified']=False;d['cycle_count']=10;report.write_text(json.dumps(d))
        with self.assertRaisesRegex(ValueError,'Unknown measurements'):
            audit_acceptance(self.repo)

if __name__ == '__main__':
    unittest.main()
