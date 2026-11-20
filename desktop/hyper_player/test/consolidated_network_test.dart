import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hyper_player/network_locations.dart';
import 'package:hyper_player/network_browser.dart';
import 'package:hyper_player/screens/network_storage_screen.dart';

void main() {
  test('SMB uses Windows UNC and contains no app-stored credentials', () {
    const location = DesktopNetworkLocation(
        name: 'NAS',
        host: '192.168.1.10',
        path: 'Media/Movies',
        protocol: DesktopNetworkProtocol.windowsShare);
    location.validate();
    expect(location.source, r'\\192.168.1.10\Media\Movies');
    final json = location.toJson();
    expect(json.keys, isNot(contains('password')));
    expect(json.keys, isNot(contains('username')));
  });
  test('HTTP resource escapes media filename and preserves HTTPS/port', () {
    const location = DesktopNetworkLocation(
        name: 'Web file',
        host: 'example.com',
        path: '/Media/My movie.mp4',
        protocol: DesktopNetworkProtocol.webFile,
        port: 8443);
    location.validate();
    expect(location.source, 'https://example.com:8443/Media/My%20movie.mp4');
  });
  test('Connection validation rejects credentials/traversal/device paths', () {
    for (final host in [
      'user:password@example.com',
      'https://example.com',
      '.',
      '?',
      'bad%host'
    ]) {
      final location = DesktopNetworkLocation(
          name: 'Bad',
          host: host,
          path: 'share/file.mp4',
          protocol: DesktopNetworkProtocol.windowsShare);
      expect(location.validate, throwsFormatException, reason: host);
    }
    for (final path in [
      '../secret',
      'Media/../secret',
      'Media/movie.mp4?token=secret',
      'C:/Windows',
      ''
    ]) {
      final location = DesktopNetworkLocation(
          name: 'Bad',
          host: 'server',
          path: path,
          protocol: DesktopNetworkProtocol.windowsShare);
      expect(location.validate, throwsFormatException, reason: path);
    }
  });
  test(
      'Malformed saved locations do not crash parsing or enable unknown protocols',
      () {
    expect(decodeNetworkLocations('{oops'), isEmpty);
    expect(
        decodeNetworkLocations(jsonEncode([
          {
            'protocol': 'ftp',
            'name': 'Bad',
            'host': 'server',
            'path': 'share',
            'secure': true
          }
        ])),
        isEmpty);
    const location = DesktopNetworkLocation(
        name: 'NAS',
        host: 'server',
        path: 'share',
        protocol: DesktopNetworkProtocol.windowsShare);
    expect(
        decodeNetworkLocations(jsonEncode([null, location.toJson()]))
            .single
            .source,
        r'\\server\share');
  });
  test('Directory browsing is nonrecursive and does not follow links',
      () async {
    final root = await Directory.systemTemp.createTemp('hyper-network-list-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/Video.mp4').writeAsString('fixture');
    await File('${root.path}/ignore.txt').writeAsString('fixture');
    final child = await Directory('${root.path}/Child').create();
    await File('${child.path}/Nested.mkv').writeAsString('fixture');
    if (!Platform.isWindows) {
      await Link('${root.path}/shortcut').create(child.path);
    }
    final result = await browseNetworkDirectory(root.path);
    expect(result.files.length, 1);
    expect(result.folders, hasLength(1));
    // Windows directory enumeration normalizes separators; compare filesystem
    // identity rather than the spelling of an equivalent folder path.
    expect(await FileSystemEntity.identical(result.folders.single, child.path),
        isTrue);
    expect(result.truncated, isFalse);
  });
  test('Directory entry limit is explicit and missing share fails', () async {
    final root = await Directory.systemTemp.createTemp('hyper-network-limit-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/a.mp4').writeAsString('a');
    await File('${root.path}/b.mp4').writeAsString('b');
    expect(
        (await browseNetworkDirectory(root.path, limit: 1)).truncated, isTrue);
    await expectLater(browseNetworkDirectory('${root.path}/missing'),
        throwsA(isA<FileSystemException>()));
  });
  testWidgets('Network storage matches Android empty state and safe add form',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester
        .pumpWidget(const MaterialApp(home: DesktopNetworkStorageScreen()));
    await tester.pumpAndSettle();
    expect(find.text('No saved network storage connections'), findsOneWidget);
    await tester.tap(find.text('Add Network Storage'));
    await tester.pumpAndSettle();
    expect(find.text('SMB (Windows/Samba)'), findsOneWidget);
    expect(find.textContaining('existing Windows network session'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsNothing);
    final ftp = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'FTP / FTPS · unavailable'));
    expect(ftp.onSelected, isNull);
  });
  testWidgets(
      'Network form validates without inventing a successful connection',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester
        .pumpWidget(const MaterialApp(home: DesktopNetworkStorageScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Network Storage'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save connection'));
    await tester.tap(find.text('Save connection'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name (up to 100 characters).'), findsOneWidget);
  });
}
