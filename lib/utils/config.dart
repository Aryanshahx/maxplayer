/// Third-party API configuration.
///
/// Values come ONLY from --dart-define (Codemagic env group
/// `keystore_credentials`): TMDB_API_KEY and OPENROUTER_API_KEY.
/// Keys are NEVER committed to the repo.
class AppConfig {
  AppConfig._();

  /// TMDB v4 read-access token (Authorization: Bearer ...).
  static const tmdbToken = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue:
        '',
  );

  /// OpenRouter key — reserved for upcoming AI features.
  static const openRouterKey = String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue:
        '',
  );
}
