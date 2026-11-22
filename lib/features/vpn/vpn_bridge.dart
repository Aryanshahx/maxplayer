import 'dart:async';
import 'package:flutter/services.dart';

/// VPN-only channel. Missing plugins must never report a fake connected state.
class VpnBridge {
  VpnBridge._();
  static final instance = VpnBridge._();
  static const channel = MethodChannel('maxplayer/vpn');
  Future<Map<String, Object?>> _map(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      final raw = await channel
          .invokeMapMethod<String, Object?>(method, args)
          .timeout(const Duration(seconds: 90));
      if (raw != null && raw['error'] != null) {
        raw['error'] =
            raw['error'].toString().toLowerCase().contains('declined')
            ? 'Android VPN permission declined.'
            : 'VPN operation failed. Check the profile, provider and network.';
      }
      return raw ??
          {
            'ok': false,
            'connected': false,
            'valid': false,
            'error': 'VPN backend unavailable on this device.',
          };
    } catch (_) {
      return {
        'ok': false,
        'connected': false,
        'valid': false,
        'error':
            'VPN operation failed or timed out. Check Android VPN settings before retrying.',
      };
    }
  }

  Future<Map<String, Object?>> provisionFreeWarpConfig() =>
      _map('provisionFreeWarpConfig');
  Future<Map<String, Object?>> provisionForeignOpenVpnConfig({
    required String countryCode,
    List<String> excludeHosts = const [],
  }) => _map('provisionForeignOpenVpnConfig', {
    'countryCode': countryCode,
    'excludeHosts': excludeHosts,
  });
  Future<Map<String, Object?>> validateWireGuardConfig(String configText) =>
      _map('validateWireGuardConfig', {'configText': configText});
  Future<Map<String, Object?>> connectVpn({
    required String configText,
    required String profileName,
    required bool appOnly,
  }) => _map('connectVpn', {
    'configText': configText,
    'profileName': profileName,
    'appOnly': appOnly,
  });
  Future<void> disconnectVpn() async {
    await _map('disconnectVpn');
  }

  Future<Map<String, Object?>> getVpnStatus() => _map('getVpnStatus');
  Future<List<Map<String, Object?>>> fetchLiveForeignCountries() async {
    final raw = await _map('fetchLiveForeignCountries');
    return (raw['countries'] as List? ?? [])
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v as Object?)))
        .toList();
  }

  Future<String?> readSecret(String key) async {
    try {
      return await channel.invokeMethod<String>('readSecret', {'key': key});
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSecret(String key, String? value) async {
    // If Keystore is unavailable keep session state only, never fall back to
    // plaintext SharedPreferences or include config data in diagnostic errors.
    try {
      await channel.invokeMethod('writeSecret', {'key': key, 'value': value});
    } catch (_) {
      /* Session-only on devices without usable Keystore. */
    }
  }
}
