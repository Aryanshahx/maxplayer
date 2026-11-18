/// Build-time token supplied by GitHub Actions. No credential fallback in source.
class AppConfig {
  AppConfig._();
  static const tmdbToken = String.fromEnvironment('TMDB_API_KEY');
}
