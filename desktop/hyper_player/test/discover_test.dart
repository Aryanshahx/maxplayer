import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/discover/tmdb.dart';
import 'package:hyper_player/utils/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Movie paging is bounded and invalid JSON tolerated', () {
    final result = parseTmdbPage(
        '{"page":2,"total_pages":9999,"results":[{"id":1,"title":"Sample","vote_average":7.4,"release_date":"2024-01-01"}]}');
    expect(result.page, 2);
    expect(result.totalPages, 500);
    expect(result.items.single.title, 'Sample');
    expect(parseTmdbPage('broken').items, isEmpty);
  });
  test('Mixed search excludes people and retains series kind', () {
    final result = parseTmdbMultiPage(
        '{"results":[{"id":1,"media_type":"person","name":"Actor"},{"id":2,"media_type":"tv","name":"Series","vote_average":8}]}');
    expect(result.items.length, 1);
    expect(result.items.single.kind, 'tv');
  });
  test('Filters retain Android catalogue categories', () {
    expect(kAllFilters.any((f) => f.key == 'bollywood'), isTrue);
    expect(kAllFilters.any((f) => f.tv), isTrue);
    expect(tmdbEndpointPath(kDiscoverFilters.first), contains('trending'));
  });
  test('Provider parsing uses India data', () {
    final providers = parseTmdbWatchProviders(
        '{"watch/providers":{"results":{"IN":{"flatrate":[{"provider_name":"Sample Provider"}]},"US":{"flatrate":[{"provider_name":"Other"}]}}}}');
    expect(providers.stream, ['Sample Provider']);
  });
  test('Hindi selection persists and fixed labels are bundled', () async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.setLanguage('hi');
    expect(AppLanguage.instance.effectiveCode, 'hi');
    expect(AppLanguage.instance.text('Language'), isNot('Language'));
    expect((await SharedPreferences.getInstance()).getString('ui.language.v1'),
        'hi');
    await AppLanguage.instance.setLanguage('en');
  });
}
