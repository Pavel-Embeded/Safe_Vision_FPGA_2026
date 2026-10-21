"""Negative controls for the new delivery boundary (no RTL test duplication)."""
from pathlib import Path
import hashlib,json,tempfile,unittest,zipfile
from verify_base_delivery import check_checkout,extract,inside,RELEASE

class DeliveryBoundary(unittest.TestCase):
    def test_bad_checksum_and_missing_file(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/RELEASE).mkdir(parents=True);(p/'source.v').write_bytes(b'approved')
            digest=hashlib.sha256(b'approved').hexdigest()
            m=dict(schema=1,qualified_modes=['base'],qualification_payload_sha256={'source.v':digest},published_source_sha256={},board_evidence_sha256={},delivery_files_sha256={})
            (p/RELEASE/'delivery.manifest.json').write_text(json.dumps(m))
            (p/'source.v').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'SHA-256 mismatch'):check_checkout(p)
            (p/'source.v').unlink()
            with self.assertRaises(FileNotFoundError):check_checkout(p)

    def test_path_escape(self):
        with tempfile.TemporaryDirectory() as d:
            for name in('../outside','/absolute','C:/drive','safe/../../out',r'safe\..\out'):
                with self.assertRaises(ValueError,msg=name):inside(Path(d),name)

    def test_zip_path_escape(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);z=p/'bad.zip'
            with zipfile.ZipFile(z,'w')as f:f.writestr('../outside','bad')
            with self.assertRaises(ValueError):extract(z,p/'out')
            self.assertFalse((p/'outside').exists())

    def test_zip_duplicate(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);z=p/'duplicate.zip'
            with zipfile.ZipFile(z,'w')as f:
                f.writestr('file','ok');f.writestr('FILE','bad')
            with self.assertRaises(ValueError):extract(z,p/'out')

    def test_good_zip(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);z=p/'good.zip'
            with zipfile.ZipFile(z,'w')as f:f.writestr('source/file.v','exact\r\n')
            extract(z,p/'out');self.assertEqual((p/'out/source/file.v').read_bytes(),b'exact\r\n')

if __name__=='__main__':unittest.main()
