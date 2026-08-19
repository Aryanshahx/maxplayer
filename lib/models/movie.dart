/// v43 Discover: data model for the online movie catalogue (TMDB).
///
/// Deliberately dependency-free: plain classes + `fromJson` on
/// `Map<String, Object?>`, so every parser here is unit-testable without a
/// device, a network or a plugin (the same style as models/playlist.dart).
library;

/// Tolerant readers - TMDB happily returns `null`, an int where a double is
/// expected, or omits a field entirely. Never throw while parsing a list of
/// 20 movies because one of them is half-filled by a community editor.
String asStr(Object? v) => v == null ? '' : v.toString();

int asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double asDouble(Object? v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

/// Nullable image path ('/abc.jpg'); '' and null both mean "no image".
String? asPath(Object? v) {
  final s = asStr(v);
  return s.isEmpty ? null : s;
}

List<Map<String, Object?>> asMapList(Object? v) {
  if (v is! List) return const [];
  final out = <Map<String, Object?>>[];
  for (final e in v) {
    if (e is Map) out.add(e.cast<String, Object?>());
  }
  return out;
}

/// "1.2K", "15K", "1.1M" - vote counts next to the rating badge.
String formatVotes(int votes) {
  if (votes < 1000) return '$votes';
  if (votes < 10000) return '${(votes / 1000).toStringAsFixed(1)}K';
  if (votes < 1000000) return '${(votes / 1000).round()}K';
  return '${(votes / 1000000).toStringAsFixed(1)}M';
}

/// One catalogue entry (a row of a TMDB list response).
class Movie {
  final int id;
  final String title;
  final String originalTitle;
  final String overview;
  final String? posterPath;
  final String? backdropPath;

  /// TMDB user score, 0..10. NOT an IMDb score - the UI labels it "TMDB".
  final double voteAverage;
  final int voteCount;

  /// 'yyyy-MM-dd', possibly '' for unscheduled titles.
  final String releaseDate;
  final List<int> genreIds;
  final String originalLanguage;
  final double popularity;

  const Movie({
    required this.id,
    required this.title,
    this.originalTitle = '',
    this.overview = '',
    this.posterPath,
    this.backdropPath,
    this.voteAverage = 0,
    this.voteCount = 0,
    this.releaseDate = '',
    this.genreIds = const [],
    this.originalLanguage = '',
    this.popularity = 0,
  });

  factory Movie.fromJson(Map<String, Object?> j) {
    final rawGenres = j['genre_ids'];
    final genres = <int>[];
    if (rawGenres is List) {
      for (final g in rawGenres) {
        final n = asInt(g);
        if (n > 0) genres.add(n);
      }
    } else {
      // /movie/{id} returns full genre objects instead of bare ids.
      for (final g in asMapList(j['genres'])) {
        final n = asInt(g['id']);
        if (n > 0) genres.add(n);
      }
    }
    return Movie(
      id: asInt(j['id']),
      title: asStr(j['title']).isEmpty ? asStr(j['name']) : asStr(j['title']),
      originalTitle: asStr(j['original_title']),
      overview: asStr(j['overview']),
      posterPath: asPath(j['poster_path']),
      backdropPath: asPath(j['backdrop_path']),
      voteAverage: asDouble(j['vote_average']),
      voteCount: asInt(j['vote_count']),
      releaseDate: asStr(j['release_date']),
      genreIds: genres,
      originalLanguage: asStr(j['original_language']),
      popularity: asDouble(j['popularity']),
    );
  }

  /// Round-trips through the on-disk cache and the watchlist setting.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'original_title': originalTitle,
        'overview': overview,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'vote_average': voteAverage,
        'vote_count': voteCount,
        'release_date': releaseDate,
        'genre_ids': genreIds,
        'original_language': originalLanguage,
        'popularity': popularity,
      };

  /// '2024' or '' - shown next to the title.
  String get year => releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';

  /// A single vote of 10/10 must not show as a 10.0 masterpiece: TMDB's own
  /// lists hide scores below a vote threshold, so we do too.
  bool get hasRating => voteCount >= 20 && voteAverage > 0;

  /// '8.4' - one decimal, the way TMDB/IMDb both display scores.
  String get ratingText => hasRating ? voteAverage.toStringAsFixed(1) : '-';

  /// True when the title is only announced/dated in the future.
  bool releasedBy(DateTime now) {
    final d = DateTime.tryParse(releaseDate);
    if (d == null) return false;
    return !d.isAfter(now);
  }
}

/// A trailer/teaser/clip attached to a movie. We only ever play YouTube
/// entries, through the official IFrame player.
class MovieVideo {
  final String id;
  final String key;
  final String name;
  final String site;
  final String type;
  final bool official;
  final String publishedAt;

  const MovieVideo({
    required this.key,
    this.id = '',
    this.name = '',
    this.site = '',
    this.type = '',
    this.official = false,
    this.publishedAt = '',
  });

  factory MovieVideo.fromJson(Map<String, Object?> j) => MovieVideo(
        id: asStr(j['id']),
        key: asStr(j['key']),
        name: asStr(j['name']),
        site: asStr(j['site']),
        type: asStr(j['type']),
        official: j['official'] == true,
        publishedAt: asStr(j['published_at']),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'key': key,
        'name': name,
        'site': site,
        'type': type,
        'official': official,
        'published_at': publishedAt,
      };

  bool get isYouTube => site.toLowerCase() == 'youtube' && key.isNotEmpty;

  /// Free YouTube-hosted still, used as the trailer list thumbnail.
  String get thumbnailUrl => 'https://i.ytimg.com/vi/$key/hqdefault.jpg';

  /// Watch page - only used by the "open in YouTube" fallback.
  String get watchUrl => 'https://www.youtube.com/watch?v=$key';
}

/// Ranking used by the detail screen: an official Trailer wins, then any
/// trailer, then teasers, then clips/featurettes. Pure so it is unit-tested.
int trailerRank(MovieVideo v) {
  final t = v.type.toLowerCase();
  if (t == 'trailer') return v.official ? 0 : 1;
  if (t == 'teaser') return v.official ? 2 : 3;
  if (t == 'clip') return 4;
  if (t == 'featurette') return 5;
  return 6;
}

/// YouTube-playable videos, best first.
List<MovieVideo> sortedTrailers(List<MovieVideo> videos) {
  final list = [for (final v in videos) if (v.isYouTube) v];
  list.sort((a, b) {
    final r = trailerRank(a).compareTo(trailerRank(b));
    if (r != 0) return r;
    // Newest first inside the same rank.
    return b.publishedAt.compareTo(a.publishedAt);
  });
  return list;
}

/// The one trailer the big "Play trailer" button plays; null = none exists.
MovieVideo? pickBestTrailer(List<MovieVideo> videos) {
  final list = sortedTrailers(videos);
  return list.isEmpty ? null : list.first;
}

class CastMember {
  final int id;
  final String name;
  final String character;
  final String? profilePath;

  const CastMember({
    required this.id,
    required this.name,
    this.character = '',
    this.profilePath,
  });

  factory CastMember.fromJson(Map<String, Object?> j) => CastMember(
        id: asInt(j['id']),
        name: asStr(j['name']),
        character: asStr(j['character']),
        profilePath: asPath(j['profile_path']),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'character': character,
        'profile_path': profilePath,
      };
}

/// Full detail payload: /movie/{id}?append_to_response=videos,credits,
/// external_ids,similar - one request instead of four.
class MovieDetails {
  final Movie movie;
  final int runtimeMinutes;
  final List<String> genres;
  final String tagline;
  final String status;

  /// 'tt1375666' - used only to open the IMDb page in a browser. We never
  /// scrape imdb.com; the score we show is TMDB's.
  final String? imdbId;
  final List<MovieVideo> videos;
  final List<CastMember> cast;
  final List<String> directors;
  final List<Movie> similar;

  const MovieDetails({
    required this.movie,
    this.runtimeMinutes = 0,
    this.genres = const [],
    this.tagline = '',
    this.status = '',
    this.imdbId,
    this.videos = const [],
    this.cast = const [],
    this.directors = const [],
    this.similar = const [],
  });

  factory MovieDetails.fromJson(Map<String, Object?> j) {
    final videosRoot = j['videos'];
    final videoList = videosRoot is Map
        ? asMapList((videosRoot.cast<String, Object?>())['results'])
        : const <Map<String, Object?>>[];

    final creditsRoot = j['credits'];
    final creditsMap =
        creditsRoot is Map ? creditsRoot.cast<String, Object?>() : null;
    final castList =
        creditsMap == null ? const <Map<String, Object?>>[] : asMapList(creditsMap['cast']);
    final crewList =
        creditsMap == null ? const <Map<String, Object?>>[] : asMapList(creditsMap['crew']);

    final similarRoot = j['similar'];
    final similarList = similarRoot is Map
        ? asMapList((similarRoot.cast<String, Object?>())['results'])
        : const <Map<String, Object?>>[];

    final external = j['external_ids'];
    final externalMap =
        external is Map ? external.cast<String, Object?>() : const <String, Object?>{};

    return MovieDetails(
      movie: Movie.fromJson(j),
      runtimeMinutes: asInt(j['runtime']),
      genres: [
        for (final g in asMapList(j['genres']))
          if (asStr(g['name']).isNotEmpty) asStr(g['name']),
      ],
      tagline: asStr(j['tagline']),
      status: asStr(j['status']),
      imdbId: asPath(j['imdb_id']) ?? asPath(externalMap['imdb_id']),
      videos: [for (final v in videoList) MovieVideo.fromJson(v)],
      // 12 faces is plenty for a horizontal strip on a cheap phone.
      cast: [
        for (final c in castList.take(12)) CastMember.fromJson(c),
      ],
      directors: [
        for (final c in crewList)
          if (asStr(c['job']).toLowerCase() == 'director') asStr(c['name']),
      ],
      similar: [
        for (final m in similarList.take(20)) Movie.fromJson(m),
      ],
    );
  }

  /// '2h 28m', '48m', '' when unknown.
  String get runtimeText {
    if (runtimeMinutes <= 0) return '';
    final h = runtimeMinutes ~/ 60;
    final m = runtimeMinutes % 60;
    if (h <= 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  MovieVideo? get bestTrailer => pickBestTrailer(videos);
}
