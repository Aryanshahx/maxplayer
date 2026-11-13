#!/usr/bin/env python3
"""Validate the XML source or bundletool-decoded FINAL AAB manifest."""
import sys
import xml.etree.ElementTree as ET
PERMISSION = 'com.google.android.gms.permission.AD_ID'
ANDROID = '{http://schemas.android.com/apk/res/android}'
def verify(path):
    root = ET.parse(path).getroot()
    matches = [p for p in root.findall('uses-permission') if p.get(ANDROID+'name') == PERMISSION]
    if not matches:
        raise ValueError('Advertising ID declaration is Yes, but AD_ID is missing from this manifest')
    if not any(p.get(ANDROID+'maxSdkVersion') is None for p in matches):
        raise ValueError('AD_ID must not be restricted by maxSdkVersion')
    return True
if __name__ == '__main__':
    if len(sys.argv) != 2: raise SystemExit('Usage: verify_ad_id.py MANIFEST_XML')
    verify(sys.argv[1])
    print('PASS: final/source manifest declares unrestricted AD_ID')
