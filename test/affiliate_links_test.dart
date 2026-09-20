import 'package:flutter_test/flutter_test.dart';

import 'package:maxplayer/utils/affiliate_links.dart';

void main() {
  test('pCloud partner URL is exactly the issued referral link over https',
      () {
    expect(kPcloudPartnerUrl, 'https://partner.pcloud.com/r/157632');
    final uri = pcloudPartnerUri();
    expect(uri.scheme, 'https');
    expect(uri.host, 'partner.pcloud.com');
    expect(uri.path, '/r/157632');
  });
}
