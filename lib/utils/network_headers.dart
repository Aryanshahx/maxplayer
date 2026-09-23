/// Branded default for our own playlist fetch + first stream open.
const String kMaxPlayerUserAgent =
    'MaxPlayer/1.0 (Linux; Android) like MX Player';

/// Last-resort stream agent: VLC is the most-whitelisted player agent on
/// IPTV feeds/CDNs (many 403 everything else on purpose to block scraping).
const String kVlcFallbackUserAgent = 'VLC/3.0.20 LibVLC/3.0.20';

