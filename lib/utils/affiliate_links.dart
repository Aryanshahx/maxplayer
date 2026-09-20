// ---------------------------------------------------------------------------
// Partner (affiliate) links — non-Amazon partners live here (pCloud now,
// NordVPN when its link arrives). Same rules as amazon_affiliate.dart:
// these URLs are public by nature (they ARE the links), hardcoding is fine,
// and every in-app placement must carry a visible "Partner link" disclosure.
// ---------------------------------------------------------------------------

/// pCloud partner referral link (issued to us by pCloud's partner program).
const String kPcloudPartnerUrl = 'https://partner.pcloud.com/r/157632';

/// Pure (unit-tested): parse once here so call sites can't typo it.
Uri pcloudPartnerUri() => Uri.parse(kPcloudPartnerUrl);
