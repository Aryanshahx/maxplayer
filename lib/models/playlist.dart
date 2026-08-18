/// v40: a NAMED, persistent playlist.
///
/// Before v40 there was only one anonymous in-memory play queue (the
/// "Build playlist" button): it vanished every time the app restarted -
/// "playlists are not saving, they disappear after reopening". Playlists
/// are now named by the user (e.g. "Movies", "Songs") and persisted as
/// JSON in the app's settings store (SharedPreferences via NativeBridge -
/// no new dependencies).
///
/// Only video PATHS are stored; thumbnails/durations are resolved from the
/// scanned library at play time (a path whose file went missing - deleted,
/// SD card removed - is skipped, never an error).
class Playlist {
  /// Unique id (creation timestamp in microseconds).
  final String id;
  final String name;

  /// Absolute video paths, in play order.
  final List<String> videoPaths;

  const Playlist({
    required this.id,
    required this.name,
    required this.videoPaths,
  });

  factory Playlist.fromJson(Map<String, Object?> json) => Playlist(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        videoPaths: [
          for (final p in (json['videoPaths'] as List? ?? const [])) '$p',
        ],
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'videoPaths': videoPaths,
      };

  Playlist copyWith({String? name, List<String>? videoPaths}) => Playlist(
        id: id,
        name: name ?? this.name,
        videoPaths: videoPaths ?? this.videoPaths,
      );
}
