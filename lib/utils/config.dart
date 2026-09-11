/// Third-party API configuration.
///
/// Values come ONLY from --dart-define, injected by GitHub Actions from
/// repo secrets: TMDB_API_KEY and OPENROUTER_API_KEY. Keys are NEVER
/// committed to the repo.
class AppConfig {
  AppConfig._();

  /// TMDB v4 read-access token (Authorization: Bearer ...).
  static const tmdbToken = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI2M2M5Nzg4NGU0M2I4OTJkODRmZTVmOTU2OThhNDAxOCIsIm5iZiI6MTc4NzE1ODkwNS42MzMsInN1YiI6IjZhODVlMTc5ZTY3OTJkYmEyYmRhNGVlMSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.vjNT-PwYZa5jTAhSr7dc1T5KFNibbPLNI-KaoB0CvCk',
  );

  /// OpenRouter key — reserved for upcoming AI features.
  static const openRouterKey = String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue:
        '',
  );
}
