from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
from run_v3_board import source_commit_binding

class SourceCommitBindingTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory()
        self.root=Path(self.temporary.name)
        self.git('init','--quiet')
        self.git('config','user.name','verification')
        self.git('config','user.email','verification@example.invalid')
        self.git('config','core.autocrlf','false')
        (self.root/'config.json').write_bytes(b'{"value":1}\r\n')
        self.git('add','config.json')
        self.git('commit','--quiet','-m','fixture with original CRLF blob')
        (self.root/'.gitattributes').write_bytes(b'* text=auto eol=lf\n')
        (self.root/'rtl.v').write_bytes(b'module fixture; endmodule\n')
        self.git('add','.gitattributes','rtl.v')
        self.git('commit','--quiet','-m','text attributes and Verilog fixture')

    def tearDown(self):self.temporary.cleanup()

    def git(self,*args):
        return subprocess.run(['git','-C',str(self.root),*args],capture_output=True,check=True).stdout

    def bind(self,names):return source_commit_binding(self.root,self.root,'HEAD',names)

    def test_exact_crlf_blob_with_later_lf_attribute(self):
        result=self.bind(['config.json'])
        self.assertTrue(result['verified'],result)
        self.assertEqual(result['raw_blob_matches'],1)
        self.assertEqual(result['git_filter_matches'],0)

    def test_checkout_line_endings_use_declared_git_filter(self):
        (self.root/'rtl.v').write_bytes(b'module fixture; endmodule\r\n')
        result=self.bind(['rtl.v'])
        self.assertTrue(result['verified'],result)
        self.assertEqual(result['raw_blob_matches'],0)
        self.assertEqual(result['git_filter_matches'],1)

    def test_changed_content_is_rejected(self):
        (self.root/'config.json').write_bytes(b'{"value":2}\r\n')
        self.assertFalse(self.bind(['config.json'])['verified'])
        (self.root/'rtl.v').write_bytes(b'module changed; endmodule\r\n')
        self.assertFalse(self.bind(['rtl.v'])['verified'])

    def test_uncommitted_dependency_is_rejected(self):
        (self.root/'extra.v').write_bytes(b'module extra; endmodule\n')
        self.assertFalse(self.bind(['extra.v'])['verified'])

if __name__=='__main__':unittest.main()
