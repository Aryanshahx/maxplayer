const notificationScreens = <String>{
  'home',
  'discover',
  'private',
  'folders',
  'playlists',
  'audio',
  'network',
  'cloud',
  'quickShare',
  'stream',
  'iptv',
  'statistics',
  'external',
};
String notificationDestination(Map<String, dynamic> data) {
  final screen = data['screen'];
  if (screen == null) {
    return data['link'] is String && (data['link'] as String).isNotEmpty
        ? 'external'
        : 'home';
  }
  return screen is String && notificationScreens.contains(screen)
      ? screen
      : 'home';
}

Uri? notificationExternalLink(Map<String, dynamic> data) {
  final link = Uri.tryParse(
    data['link'] is String ? data['link'] as String : '',
  );
  return link != null &&
          link.scheme == 'https' &&
          link.host.isNotEmpty &&
          link.userInfo.isEmpty
      ? link
      : null;
}
