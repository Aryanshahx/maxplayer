#!/usr/bin/env python3
"""Reject advertising permissions in ad-free source and decoded AAB manifests.

Source manifests may contain tools:node="remove" merger directives. These
are NOT permission grants. The final bundletool manifest must contain no
advertising permission grant. Never reintroduce AD_ID to satisfy an old test.
"""
import sys
import xml.etree.ElementTree as ET

PERMISSION = 'com.google.android.gms.permission.AD_ID'
FORBIDDEN = {
    PERMISSION,
    'android.permission.ACCESS_ADSERVICES_AD_ID',
    'android.permission.ACCESS_ADSERVICES_ATTRIBUTION',
    'android.permission.ACCESS_ADSERVICES_TOPICS',
}
ANDROID = '{http://schemas.android.com/apk/res/android}'
TOOLS = '{http://schemas.android.com/tools}'


def verify(path, final=False):
    root = ET.parse(path).getroot()
    if root.tag != 'manifest':
        raise ValueError('Expected Android manifest XML')
    for node in root:
        if node.tag not in ('uses-permission', 'uses-permission-sdk-23', 'uses-permission-sdk-m'):
            continue
        name = node.get(ANDROID + 'name')
        if name in FORBIDDEN and (final or node.get(TOOLS + 'node') not in ('remove', 'removeAll')):
            raise ValueError('Ad-free build unexpectedly grants advertising permission: ' + name)
    for node in root.findall('./application/meta-data'):
        if node.get(ANDROID + 'name') == 'com.google.android.gms.ads.APPLICATION_ID' and node.get(TOOLS + 'node') != 'remove':
            raise ValueError('Ad-free build still contains AdMob application metadata')
    return True


if __name__ == '__main__':
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] != '--final'):
        raise SystemExit('Usage: verify_ad_id.py MANIFEST_XML [--final]')
    verify(sys.argv[1], final=len(sys.argv) == 3)
    print('PASS: ad-free manifest has no advertising permission grants or AdMob app metadata')
