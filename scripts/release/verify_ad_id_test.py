import tempfile
import unittest
from pathlib import Path
from verify_ad_id import verify, FORBIDDEN


class ManifestTests(unittest.TestCase):
    def check_xml(self, inner):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'manifest.xml'
            p.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools">' + inner + '</manifest>')
            return verify(p)

    def test_missing_is_correct_for_ad_free_bundle(self):
        self.assertTrue(self.check_xml(''))

    def test_source_removal_directives_are_not_permission_grants(self):
        for name in FORBIDDEN:
            self.assertTrue(self.check_xml(f'<uses-permission android:name="{name}" tools:node="remove"/>'))

    def test_every_advertising_permission_is_rejected(self):
        for name in FORBIDDEN:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.check_xml(f'<uses-permission android:name="{name}"/>')

    def test_capped_permission_is_still_rejected(self):
        with self.assertRaises(ValueError):
            self.check_xml('<uses-permission android:name="com.google.android.gms.permission.AD_ID" android:maxSdkVersion="32"/>')

    def test_sdk_specific_permission_is_rejected(self):
        with self.assertRaises(ValueError):
            self.check_xml('<uses-permission-sdk-23 android:name="com.google.android.gms.permission.AD_ID"/>')

    def test_admob_metadata_is_rejected(self):
        with self.assertRaises(ValueError):
            self.check_xml('<application><meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="test"/></application>')

    def test_unrelated_permissions_remain_valid(self):
        self.assertTrue(self.check_xml('<uses-permission android:name="android.permission.INTERNET"/>'))

    def test_final_manifest_rejects_even_a_surviving_merger_directive(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'final.xml'
            p.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools"><uses-permission android:name="com.google.android.gms.permission.AD_ID" tools:node="remove"/></manifest>')
            with self.assertRaises(ValueError):
                verify(p, final=True)

    def test_non_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'wrong.xml'
            p.write_text('<wrong/>')
            with self.assertRaises(ValueError):
                verify(p)


if __name__ == '__main__':
    unittest.main()
