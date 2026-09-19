import 'package:flutter/material.dart';

/// v1.0.20: the two 2x2 quick-tile pages on the library header as PURE
/// DATA. Ordering is user-specified and unit-tested:
///
///   page 1: Private Space · Playlists · Folders · AUDIO
///   page 2: Network Storage · CLOUD STORAGE · Open Stream · Quick Share
///
/// (v1.0.20 replaced "File Manager" with "Audio" and then interchanged
/// the positions of the Cloud Storage and Audio buttons.)
class QuickTileSpec {
  const QuickTileSpec(this.id, this.icon, this.label);

  /// Stable machine id — this is what the tests assert on.
  final String id;
  final IconData icon;
  final String label;
}

const List<QuickTileSpec> kQuickTilesPage1 = [
  QuickTileSpec('privateSpace', Icons.lock_outline_rounded, 'Private Space'),
  QuickTileSpec('playlists', Icons.queue_music_outlined, 'Playlists'),
  QuickTileSpec('folders', Icons.folder_outlined, 'Folders'),
  QuickTileSpec('audio', Icons.music_note_outlined, 'Audio'),
];

const List<QuickTileSpec> kQuickTilesPage2 = [
  QuickTileSpec('networkStorage', Icons.dns_outlined, 'Network Storage'),
  QuickTileSpec('cloudStorage', Icons.cloud_queue_outlined, 'Cloud Storage'),
  QuickTileSpec('openStream', Icons.link, 'Open Stream(iptv)'),
  QuickTileSpec('quickShare', Icons.ios_share, 'Quick Share'),
];
