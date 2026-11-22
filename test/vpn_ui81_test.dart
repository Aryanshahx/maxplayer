import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maxplayer/features/vpn/vpn_bridge.dart';
import 'package:maxplayer/features/vpn/vpn_controller.dart';
import 'package:maxplayer/features/vpn/vpn_screen.dart';
import 'package:maxplayer/theme.dart';
import 'package:maxplayer/utils/app_language.dart';
import 'package:maxplayer/utils/quick_tiles.dart';
import 'package:maxplayer/widgets/cine_ui.dart';

const config =
    '[Interface]\nPrivateKey = TEST_ONLY\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = TEST_ONLY\nEndpoint = example.test:51820';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppColors.brightness = Brightness.light;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(VpnBridge.channel, null);
    AppColors.brightness = Brightness.dark;
  });
  test(
    'Cloud Storage tile is replaced by VPN without changing other quick actions',
    () {
      expect(kQuickTilesPage2.map((e) => e.id), [
        'networkStorage',
        'vpn',
        'openStream',
        'quickShare',
      ]);
      expect(kQuickTilesPage1.length + kQuickTilesPage2.length, 8);
    },
  );
  test(
    'borderless translated inputs never inherit a second filled rectangle',
    () {
      const borderless = LInputDecoration(border: InputBorder.none);
      expect(borderless.filled, isFalse);
      expect(
        borderless
            .applyDefaults(
              buildAppTheme(brightness: Brightness.light).inputDecorationTheme,
            )
            .filled,
        isFalse,
      );
      const explicit = LInputDecoration(border: InputBorder.none, filled: true);
      expect(explicit.filled, isTrue);
      expect(const LInputDecoration().filled, isNull);
    },
  );
  test(
    'missing native backend cannot fabricate a working VPN or valid config',
    () async {
      final result = await VpnBridge.instance.connectVpn(
        configText: config,
        profileName: 'test',
        appOnly: true,
      );
      expect(result['connected'], isFalse);
      expect(result['ok'], isFalse);
      expect(
        (await VpnBridge.instance.validateWireGuardConfig(config))['valid'],
        isFalse,
      );
      expect(
        (await VpnBridge.instance.provisionFreeWarpConfig())['ok'],
        isFalse,
      );
    },
  );
  test(
    'native error messages cannot leak imported secret config values',
    () async {
      messenger.setMockMethodCallHandler(
        VpnBridge.channel,
        (call) async => {'ok': false, 'error': 'PrivateKey = SECRET_EXAMPLE'},
      );
      final result = await VpnBridge.instance.connectVpn(
        configText: config,
        profileName: 'test',
        appOnly: true,
      );
      expect(result['error'], isNot(contains('SECRET_EXAMPLE')));
    },
  );
  test(
    'WARP and app-only are defaults; no auto-connect on controller construction',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(VpnBridge.channel, (call) async {
        calls.add(call.method);
        return {'connected': false};
      });
      final vpn = VpnController(
        await SharedPreferences.getInstance(),
        enableNativePolling: false,
      );
      expect(vpn.selectedProfileId, VpnController.builtInWarpId);
      expect(vpn.appOnly, isTrue);
      expect(vpn.isConnected, isFalse);
      expect(calls, isEmpty);
      vpn.dispose();
    },
  );
  test(
    'declined WARP cannot silently switch to a different relay provider',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(VpnBridge.channel, (call) async {
        calls.add(call.method);
        if (call.method == 'provisionFreeWarpConfig') {
          return {'ok': false, 'error': 'declined'};
        }
        return {'ok': true};
      });
      final vpn = VpnController(
        await SharedPreferences.getInstance(),
        enableNativePolling: false,
      );
      expect(await vpn.connect(), isFalse);
      expect(vpn.isConnected, isFalse);
      expect(vpn.isBusy, isFalse);
      expect(calls, isNot(contains('provisionForeignOpenVpnConfig')));
      vpn.dispose();
    },
  );
  test(
    'custom keys are stored by secure native bridge, not preferences',
    () async {
      final writes = <Map<Object?, Object?>>[];
      messenger.setMockMethodCallHandler(VpnBridge.channel, (call) async {
        if (call.method == 'validateWireGuardConfig') return {'valid': true};
        if (call.method == 'writeSecret') {
          writes.add(call.arguments as Map);
          return true;
        }
        return null;
      });
      final prefs = await SharedPreferences.getInstance();
      final vpn = VpnController(prefs, enableNativePolling: false);
      expect(
        await vpn.addCustomProfile(
          name: 'My profile',
          countryLabel: '',
          configText: config,
        ),
        isNull,
      );
      await Future<void>.delayed(Duration.zero);
      expect(vpn.customProfiles.length, 1);
      expect(writes.single['value'].toString(), contains('TEST_ONLY'));
      expect(
        prefs.getKeys().any(
          (key) => prefs.get(key).toString().contains('TEST_ONLY'),
        ),
        isFalse,
      );
      await vpn.removeCustomProfile(vpn.customProfiles.single.id);
      await Future<void>.delayed(Duration.zero);
      expect(vpn.customProfiles, isEmpty);
      expect(writes.last['value'].toString(), isNot(contains('TEST_ONLY')));
      vpn.dispose();
    },
  );
  test(
    'import rejects scripts, oversized profiles and missing external credentials',
    () async {
      final vpn = VpnController(
        await SharedPreferences.getInstance(),
        enableNativePolling: false,
      );
      for (final invalid in [
        'remote example.test 1194\nup /tmp/script',
        'remote example.test 1194\nauth-user-pass',
        'x' * 65537,
      ]) {
        expect(
          await vpn.addCustomProfile(
            name: 'bad',
            countryLabel: '',
            configText: invalid,
          ),
          isNotNull,
        );
      }
      expect(vpn.customProfiles, isEmpty);
      vpn.dispose();
    },
  );
  test(
    'VPN source uses encrypted no-backup key storage and HTTPS-only server lists',
    () {
      final java = File(
        'android/app/src/main/java/com/hypertechlabs/maxplayer/MaxVpnManager.java',
      ).readAsStringSync();
      final vault = File(
        'android/app/src/main/java/com/hypertechlabs/maxplayer/VpnSecretStore.java',
      ).readAsStringSync();
      expect(java, isNot(contains('http://130.158.75.39')));
      expect(java, isNot(contains('@SECLEVEL=0')));
      expect(java, contains('waitForWireGuardPeerHandshake'));
      expect(java, isNot(contains('.putString(PREF_RISEUP_KEY')));
      expect(vault, contains('AES/GCM/NoPadding'));
      expect(vault, contains('getNoBackupFilesDir'));
      expect(vault, contains('AndroidKeyStore'));
      expect(java, contains('appContext.getPackageName()'));
    },
  );
  testWidgets(
    'opening VPN shows disclosure before any native/network provisioning',
    (tester) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(VpnBridge.channel, (call) async {
        calls.add(call.method);
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.light),
          home: const VpnEntryScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(vpnDisclosure), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Agree and continue'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Agree and continue'), findsOneWidget);
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'Discover splash uses $brightness palette, fades smoothly and finishes once',
      (tester) async {
        var finished = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness: brightness),
            home: Scaffold(body: CineBoot(onFinished: () => finished++)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(finished, 0);
        final box = tester.widget<ColoredBox>(
          find.descendant(
            of: find.byType(CineBoot),
            matching: find.byType(ColoredBox),
          ),
        );
        expect(
          box.color,
          buildAppTheme(brightness: brightness).scaffoldBackgroundColor,
        );
        await tester.pump(const Duration(milliseconds: 450));
        final opacity = tester.widget<Opacity>(
          find.descendant(
            of: find.byType(CineBoot),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacity.opacity, inExclusiveRange(0, 1));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 1));
        expect(finished, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'reduced-motion Discover splash finishes without waiting for animation',
    (tester) async {
      var finished = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: CineBoot(onFinished: () => finished++),
          ),
        ),
      );
      await tester.pump();
      expect(finished, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
