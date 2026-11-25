/// Branded default for our own playlist fetch + first stream open.
const String kMaxPlayerUserAgent =
    'RunXPlayer/1.0 (Linux; Android)';

/// Last-resort stream agent: VLC is the most-whitelisted player agent on
/// IPTV feeds/CDNs (many 403 everything else on purpose to block scraping).
const String kVlcFallbackUserAgent = 'VLC/3.0.20 LibVLC/3.0.20';

