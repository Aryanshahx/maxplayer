import tempfile
import unittest
from pathlib import Path
from verify_ad_id import verify

class ManifestTests(unittest.TestCase):
    def check_xml(self, permission):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'manifest.xml'
            p.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android">'+permission+'</manifest>')
            return verify(p)
    def test_present(self):
        self.assertTrue(self.check_xml('<uses-permission android:name="com.google.android.gms.permission.AD_ID"/>'))
    def test_missing(self):
        with self.assertRaises(ValueError): self.check_xml('')
    def test_capped(self):
        with self.assertRaises(ValueError): self.check_xml('<uses-permission android:name="com.google.android.gms.permission.AD_ID" android:maxSdkVersion="32"/>')

if __name__=='__main__': unittest.main()
