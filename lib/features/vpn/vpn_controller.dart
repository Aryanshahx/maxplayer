import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:openvpn_flutter/openvpn_flutter.dart' as ovpn;
import 'package:shared_preferences/shared_preferences.dart';

import 'vpn_bridge.dart';

enum VpnProtocol { wireguard, openvpn }

class VpnProfile {
  const VpnProfile({
    required this.id,
    required this.name,
    required this.countryLabel,
    required this.configText,
    this.flagEmoji = '🌐',
    this.countryCode = '',
    this.protocol = VpnProtocol.wireguard,
    this.isBuiltInWarp = false,
    this.isBuiltInForeign = false,
  });

  final String id;
  final String name;
  final String countryLabel;
  final String configText;
  final String flagEmoji;
  final String countryCode;
  final VpnProtocol protocol;
  final bool isBuiltInWarp;
  final bool isBuiltInForeign;

  bool get isBuiltIn => isBuiltInWarp || isBuiltInForeign;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'countryLabel': countryLabel,
    'configText': configText,
    'flagEmoji': flagEmoji,
    'countryCode': countryCode,
    'protocol': protocol.name,
  };

  factory VpnProfile.fromJson(Map<String, Object?> map) {
    final String rawProto = (map['protocol']?.toString() ?? 'wireguard').trim();
    return VpnProfile(
      id: (map['id']?.toString() ?? '').trim(),
      name: (map['name']?.toString() ?? 'Custom VPN').trim(),
      countryLabel: (map['countryLabel']?.toString() ?? 'Custom').trim(),
      configText: (map['configText']?.toString() ?? '').trim(),
      flagEmoji: (map['flagEmoji']?.toString() ?? '🌐').trim(),
      countryCode: (map['countryCode']?.toString() ?? '').trim(),
      protocol: rawProto == 'openvpn'
          ? VpnProtocol.openvpn
          : VpnProtocol.wireguard,
    );
  }
}

class VpnController extends ChangeNotifier {
  VpnController(
    this._prefs, {
    this.enableNativePolling = true,
    http.Client? client,
    Map<String, String> secrets = const {},
  }) : _client = client ?? http.Client(),
       _secrets = Map<String, String>.of(secrets) {
    _load();
    if (enableNativePolling) {
      unawaited(_initEngines());
    }
  }

  static const String builtInWarpId = 'builtin_warp';
  static const String defaultForeignUsId = 'foreign_us';

  static const String _keyWarpConfig = 'max.vpn.warpConfig.v6';
  static const String _keyCustomProfiles = 'max.vpn.customProfiles.v7';
  static const String _keySelectedProfileId = 'max.vpn.selectedProfile.v7';
  static const String _keyAppOnly = 'max.vpn.appOnly.v6';

  static const List<VpnProfile> _coreForeignProfiles = <VpnProfile>[
    VpnProfile(
      id: 'foreign_auto',
      name: 'Automatic OpenVPN relay',
      countryLabel: 'Available third-party relay',
      configText: '',
      flagEmoji: '🌍',
      countryCode: 'AUTO_FOREIGN',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: defaultForeignUsId,
      name: 'United States',
      countryLabel: 'Americas • High-Speed',
      configText: '',
      flagEmoji: '🇺🇸',
      countryCode: 'US',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_gb',
      name: 'United Kingdom',
      countryLabel: 'London • Europe',
      configText: '',
      flagEmoji: '🇬🇧',
      countryCode: 'GB',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_de',
      name: 'Germany',
      countryLabel: 'Frankfurt • Europe',
      configText: '',
      flagEmoji: '🇩🇪',
      countryCode: 'DE',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_nl',
      name: 'Netherlands',
      countryLabel: 'Amsterdam • Europe',
      configText: '',
      flagEmoji: '🇳🇱',
      countryCode: 'NL',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_fr',
      name: 'France',
      countryLabel: 'Paris • Europe',
      configText: '',
      flagEmoji: '🇫🇷',
      countryCode: 'FR',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_ch',
      name: 'Switzerland',
      countryLabel: 'Zurich • Privacy Hub',
      configText: '',
      flagEmoji: '🇨🇭',
      countryCode: 'CH',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_ca',
      name: 'Canada',
      countryLabel: 'Montreal / Toronto',
      configText: '',
      flagEmoji: '🇨🇦',
      countryCode: 'CA',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_jp',
      name: 'Japan',
      countryLabel: 'Tokyo • East Asia',
      configText: '',
      flagEmoji: '🇯🇵',
      countryCode: 'JP',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_sg',
      name: 'Singapore',
      countryLabel: 'Singapore • Low Ping Asia',
      configText: '',
      flagEmoji: '🇸🇬',
      countryCode: 'SG',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_kr',
      name: 'South Korea',
      countryLabel: 'Seoul • East Asia',
      configText: '',
      flagEmoji: '🇰🇷',
      countryCode: 'KR',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_au',
      name: 'Australia',
      countryLabel: 'Sydney • Oceania',
      configText: '',
      flagEmoji: '🇦🇺',
      countryCode: 'AU',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_se',
      name: 'Sweden',
      countryLabel: 'Stockholm • Nordics',
      configText: '',
      flagEmoji: '🇸🇪',
      countryCode: 'SE',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_no',
      name: 'Norway',
      countryLabel: 'Oslo • Nordics',
      configText: '',
      flagEmoji: '🇳🇴',
      countryCode: 'NO',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_fi',
      name: 'Finland',
      countryLabel: 'Helsinki • Nordics',
      configText: '',
      flagEmoji: '🇫🇮',
      countryCode: 'FI',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_dk',
      name: 'Denmark',
      countryLabel: 'Copenhagen • Nordics',
      configText: '',
      flagEmoji: '🇩🇰',
      countryCode: 'DK',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_es',
      name: 'Spain',
      countryLabel: 'Madrid • Europe',
      configText: '',
      flagEmoji: '🇪🇸',
      countryCode: 'ES',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_it',
      name: 'Italy',
      countryLabel: 'Milan • Europe',
      configText: '',
      flagEmoji: '🇮🇹',
      countryCode: 'IT',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_at',
      name: 'Austria',
      countryLabel: 'Vienna • Europe',
      configText: '',
      flagEmoji: '🇦🇹',
      countryCode: 'AT',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_be',
      name: 'Belgium',
      countryLabel: 'Brussels • Europe',
      configText: '',
      flagEmoji: '🇧🇪',
      countryCode: 'BE',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_ie',
      name: 'Ireland',
      countryLabel: 'Dublin • Europe',
      configText: '',
      flagEmoji: '🇮🇪',
      countryCode: 'IE',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_pt',
      name: 'Portugal',
      countryLabel: 'Lisbon • Europe',
      configText: '',
      flagEmoji: '🇵🇹',
      countryCode: 'PT',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_pl',
      name: 'Poland',
      countryLabel: 'Warsaw • Europe',
      configText: '',
      flagEmoji: '🇵🇱',
      countryCode: 'PL',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_cz',
      name: 'Czechia',
      countryLabel: 'Prague • Europe',
      configText: '',
      flagEmoji: '🇨🇿',
      countryCode: 'CZ',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_ro',
      name: 'Romania',
      countryLabel: 'Bucharest • Europe',
      configText: '',
      flagEmoji: '🇷🇴',
      countryCode: 'RO',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_ua',
      name: 'Ukraine',
      countryLabel: 'Kyiv • Eastern Europe',
      configText: '',
      flagEmoji: '🇺🇦',
      countryCode: 'UA',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_hk',
      name: 'Hong Kong',
      countryLabel: 'Hong Kong • Asia',
      configText: '',
      flagEmoji: '🇭🇰',
      countryCode: 'HK',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_tw',
      name: 'Taiwan',
      countryLabel: 'Taipei • East Asia',
      configText: '',
      flagEmoji: '🇹🇼',
      countryCode: 'TW',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_th',
      name: 'Thailand',
      countryLabel: 'Bangkok • Southeast Asia',
      configText: '',
      flagEmoji: '🇹🇭',
      countryCode: 'TH',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_vn',
      name: 'Vietnam',
      countryLabel: 'Ho Chi Minh • Asia',
      configText: '',
      flagEmoji: '🇻🇳',
      countryCode: 'VN',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_my',
      name: 'Malaysia',
      countryLabel: 'Kuala Lumpur • Asia',
      configText: '',
      flagEmoji: '🇲🇾',
      countryCode: 'MY',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_id',
      name: 'Indonesia',
      countryLabel: 'Jakarta • Southeast Asia',
      configText: '',
      flagEmoji: '🇮🇩',
      countryCode: 'ID',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_ph',
      name: 'Philippines',
      countryLabel: 'Manila • Southeast Asia',
      configText: '',
      flagEmoji: '🇵🇭',
      countryCode: 'PH',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_nz',
      name: 'New Zealand',
      countryLabel: 'Auckland • Oceania',
      configText: '',
      flagEmoji: '🇳🇿',
      countryCode: 'NZ',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_br',
      name: 'Brazil',
      countryLabel: 'Sao Paulo • South America',
      configText: '',
      flagEmoji: '🇧🇷',
      countryCode: 'BR',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_mx',
      name: 'Mexico',
      countryLabel: 'Mexico City • Americas',
      configText: '',
      flagEmoji: '🇲🇽',
      countryCode: 'MX',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_ar',
      name: 'Argentina',
      countryLabel: 'Buenos Aires • Americas',
      configText: '',
      flagEmoji: '🇦🇷',
      countryCode: 'AR',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_cl',
      name: 'Chile',
      countryLabel: 'Santiago • South America',
      configText: '',
      flagEmoji: '🇨🇱',
      countryCode: 'CL',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_co',
      name: 'Colombia',
      countryLabel: 'Bogota • South America',
      configText: '',
      flagEmoji: '🇨🇴',
      countryCode: 'CO',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_ae',
      name: 'United Arab Emirates',
      countryLabel: 'Dubai • Middle East',
      configText: '',
      flagEmoji: '🇦🇪',
      countryCode: 'AE',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_il',
      name: 'Israel',
      countryLabel: 'Tel Aviv • Middle East',
      configText: '',
      flagEmoji: '🇮🇱',
      countryCode: 'IL',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_tr',
      name: 'Turkey',
      countryLabel: 'Istanbul • Eurasia',
      configText: '',
      flagEmoji: '🇹🇷',
      countryCode: 'TR',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
    VpnProfile(
      id: 'foreign_za',
      name: 'South Africa',
      countryLabel: 'Johannesburg • Africa',
      configText: '',
      flagEmoji: '🇿🇦',
      countryCode: 'ZA',
      protocol: VpnProtocol.openvpn,
      isBuiltInForeign: true,
    ),
  ];

  final Map<String, String> _secrets;
  static Future<VpnController> create() async {
    final prefs = await SharedPreferences.getInstance();
    final secrets = <String, String>{};
    for (final key in [_keyWarpConfig, _keyCustomProfiles]) {
      final value = await VpnBridge.instance.readSecret(key);
      if (value != null) secrets[key] = value;
    }
    return VpnController(prefs, secrets: secrets);
  }

  Future<void> _saveSecret(String key, String? value) async {
    if (value == null) {
      _secrets.remove(key);
    } else {
      _secrets[key] = value;
    }
    await VpnBridge.instance.writeSecret(key, value);
  }

  // Async engine callbacks can outlive a route; the app-scoped controller
  // remains alive between visits and is never disposed by the VPN screen.
  final SharedPreferences _prefs;
  final bool enableNativePolling;
  final http.Client _client;

  Timer? _statsTimer;
  ovpn.OpenVPN? _openVpnEngine;
  bool _openVpnReady = false;
  VpnProtocol? _activeEngineProtocol;
  final Set<String> _sessionExcludedHosts = <String>{};
  VoidCallback? onTunnelConnected;

  String _cachedWarpConfig = '';
  List<VpnProfile> _dynamicForeignProfiles = <VpnProfile>[];
  List<VpnProfile> _customProfiles = <VpnProfile>[];
  String _selectedProfileId = defaultForeignUsId;
  bool _appOnly = true;
  bool _refreshingServers = false;

  bool _isConnected = false;
  bool _isBusy = false;
  String? _statusMessage;
  String? _errorMessage;
  int _rxBytes = 0;
  int _txBytes = 0;
  String? _exitIp;
  String? _exitCountry;

  bool get isConnected => _isConnected;
  bool get isBusy => _isBusy;
  bool get isRefreshingServers => _refreshingServers;
  bool get appOnly => _appOnly;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  int get rxBytes => _rxBytes;
  int get txBytes => _txBytes;
  String? get exitIp => _exitIp;
  String? get exitCountry => _exitCountry;
  String get selectedProfileId => _selectedProfileId;

  VpnProfile get builtInWarpProfile => VpnProfile(
    id: builtInWarpId,
    name: 'Cloudflare WARP',
    countryLabel: 'Cloudflare • WireGuard • location chosen by provider',
    configText: _cachedWarpConfig,
    flagEmoji: '⚡',
    countryCode: 'WARP',
    protocol: VpnProtocol.wireguard,
    isBuiltInWarp: true,
  );

  List<VpnProfile> get foreignProfiles => <VpnProfile>[
    ..._coreForeignProfiles,
    ..._dynamicForeignProfiles,
  ];

  List<VpnProfile> get allProfiles => <VpnProfile>[
    ..._coreForeignProfiles,
    ..._dynamicForeignProfiles,
    builtInWarpProfile,
    ..._customProfiles,
  ];

  List<VpnProfile> get customProfiles =>
      List<VpnProfile>.unmodifiable(_customProfiles);

  VpnProfile get selectedProfile {
    for (final VpnProfile p in allProfiles) {
      if (p.id == _selectedProfileId) {
        return p;
      }
    }
    return _coreForeignProfiles[1]; // United States default
  }

  void _load() {
    _cachedWarpConfig = (_secrets[_keyWarpConfig] ?? '').replaceAllMapped(
      RegExp(r'^(\s*Endpoint\s*=\s*[^:\s]+):0\s*$', multiLine: true),
      (Match m) => '${m.group(1)}:2408',
    );
    _selectedProfileId =
        _prefs.getString(_keySelectedProfileId) ?? builtInWarpId;
    _appOnly = _prefs.getBool(_keyAppOnly) ?? true;

    final String? rawProfiles = _secrets[_keyCustomProfiles];
    if (rawProfiles != null && rawProfiles.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(rawProfiles);
        if (decoded is List<Object?>) {
          _customProfiles = decoded
              .whereType<Map<String, Object?>>()
              .map(VpnProfile.fromJson)
              .where(
                (VpnProfile p) => p.id.isNotEmpty && p.configText.isNotEmpty,
              )
              .toList();
        }
      } on FormatException {
        _customProfiles = <VpnProfile>[];
      }
    }
    if (!allProfiles.any((VpnProfile p) => p.id == _selectedProfileId)) {
      _selectedProfileId = defaultForeignUsId;
    }
  }

  Future<void> _initEngines() async {
    await syncNativeStatus();
    await _ensureOpenVpnEngine();
  }

  int _lastStatsNotifyMs = 0;

  Future<ovpn.OpenVPN?> _ensureOpenVpnEngine() async {
    if (!enableNativePolling) {
      return null;
    }
    if (_openVpnEngine != null && _openVpnReady) {
      return _openVpnEngine;
    }
    final ovpn.OpenVPN engine = ovpn.OpenVPN(
      onVpnStatusChanged: (ovpn.VpnStatus? status) {
        if (status == null || _activeEngineProtocol != VpnProtocol.openvpn) {
          return;
        }
        final int rx = int.tryParse(status.byteIn ?? '0') ?? 0;
        final int tx = int.tryParse(status.byteOut ?? '0') ?? 0;
        if (rx != _rxBytes || tx != _txBytes) {
          _rxBytes = rx;
          _txBytes = tx;
          final int now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastStatsNotifyMs >= 1000) {
            _lastStatsNotifyMs = now;
            notifyListeners();
          }
        }
      },
      onVpnStageChanged: (ovpn.VPNStage stage, String rawStage) {
        if (_activeEngineProtocol != VpnProtocol.openvpn) {
          return;
        }
        if (stage == ovpn.VPNStage.connected) {
          _isConnected = true;
          _isBusy = false;
          _statusMessage = null;
          _errorMessage = null;
          unawaited(refreshExitIpInfo());
          notifyListeners();
        } else if (stage.isConnecting) {
          _statusMessage = _humanStageLabel(stage);
          notifyListeners();
        } else if (stage == ovpn.VPNStage.disconnected && !_isBusy) {
          _isConnected = false;
          _statusMessage = null;
          notifyListeners();
        }
      },
    );
    try {
      await engine.initialize(
        localizedDescription: 'Max Player VPN',
        showTrafficInNotification: true,
        lastStage: (ovpn.VPNStage stage) {
          if (stage == ovpn.VPNStage.connected) {
            _activeEngineProtocol = VpnProtocol.openvpn;
            _isConnected = true;
            unawaited(refreshExitIpInfo());
            notifyListeners();
          }
        },
      );
      _openVpnEngine = engine;
      _openVpnReady = true;
      return engine;
    } catch (_) {
      return null;
    }
  }

  String _humanStageLabel(ovpn.VPNStage stage) {
    return switch (stage) {
      ovpn.VPNStage.prepare => 'Waiting for VPN permission',
      ovpn.VPNStage.resolve => 'Resolving server',
      ovpn.VPNStage.tcp_connect ||
      ovpn.VPNStage.udp_connect ||
      ovpn.VPNStage.wait_connection => 'Securing connection',
      ovpn.VPNStage.authenticating ||
      ovpn.VPNStage.authentication => 'Verifying security',
      ovpn.VPNStage.get_config ||
      ovpn.VPNStage.assign_ip ||
      ovpn.VPNStage.add_routes => 'Assigning IP address',
      _ => 'Connecting',
    };
  }

  Future<void> refreshLiveForeignServers() async {
    if (_refreshingServers) return;
    _refreshingServers = true;
    notifyListeners();
    try {
      final List<Map<String, Object?>> countries = await VpnBridge.instance
          .fetchLiveForeignCountries()
          .timeout(
            const Duration(seconds: 4),
            onTimeout: () => const <Map<String, Object?>>[],
          );
      final Set<String> coreCodes = _coreForeignProfiles
          .map((VpnProfile p) => p.countryCode)
          .toSet();
      final List<VpnProfile> extras = <VpnProfile>[];
      for (final Map<String, Object?> c in countries) {
        final String code = (c['countryCode']?.toString() ?? '')
            .trim()
            .toUpperCase();
        final String name = (c['countryName']?.toString() ?? '').trim();
        final int count = (c['serverCount'] is num)
            ? (c['serverCount']! as num).toInt()
            : 1;
        if (code.length != 2 ||
            code == 'IN' ||
            coreCodes.contains(code) ||
            name.isEmpty) {
          continue;
        }
        extras.add(
          VpnProfile(
            id: 'foreign_${code.toLowerCase()}',
            name: name,
            countryLabel: '$count live foreign relay${count == 1 ? '' : 's'}',
            configText: '',
            flagEmoji: flagEmojiForCountryCode(code),
            countryCode: code,
            protocol: VpnProtocol.openvpn,
            isBuiltInForeign: true,
          ),
        );
      }
      if (extras.isNotEmpty) {
        _dynamicForeignProfiles = extras;
      }
    } catch (_) {
    } finally {
      _refreshingServers = false;
      notifyListeners();
    }
  }

  static String flagEmojiForCountryCode(String cc) {
    final String upper = cc.trim().toUpperCase();
    if (upper.length != 2) return '🌐';
    final int first = upper.codeUnitAt(0);
    final int second = upper.codeUnitAt(1);
    if (first < 65 || first > 90 || second < 65 || second > 90) {
      return '🌐';
    }
    return String.fromCharCodes(<int>[
      0x1F1E6 + first - 65,
      0x1F1E6 + second - 65,
    ]);
  }

  Future<void> _persistCustomProfiles() async {
    await _saveSecret(
      _keyCustomProfiles,
      jsonEncode(_customProfiles.map((VpnProfile p) => p.toJson()).toList()),
    );
  }

  Future<void> setAppOnly(bool value) async {
    if (_appOnly == value) return;
    _appOnly = value;
    notifyListeners();
    unawaited(_prefs.setBool(_keyAppOnly, value));
    if (_isConnected) {
      await reconnect();
    }
  }

  Future<void> selectProfile(String profileId) async {
    if (_selectedProfileId == profileId) return;
    if (!allProfiles.any((VpnProfile p) => p.id == profileId)) return;
    _selectedProfileId = profileId;
    _errorMessage = null;
    notifyListeners();
    unawaited(_prefs.setString(_keySelectedProfileId, profileId));
    if (_isConnected) {
      await reconnect();
    }
  }

  Future<String?> addCustomProfile({
    required String name,
    required String countryLabel,
    required String configText,
  }) async {
    final String cleanConfig = configText.trim();
    if (cleanConfig.length > 65536 || _customProfiles.length >= 20) {
      return 'Use a profile under 64 KB; a maximum of 20 profiles can be stored.';
    }
    if (_customProfiles.fold<int>(
              0,
              (size, profile) => size + profile.configText.length,
            ) +
            cleanConfig.length >
        384000) {
      return 'Stored profiles are too large. Delete an unused profile first.';
    }
    if (cleanConfig.isEmpty) {
      return 'Paste a WireGuard (.conf) or OpenVPN (.ovpn) config first.';
    }

    final bool looksLikeOpenVpn =
        cleanConfig.contains('<ca>') ||
        RegExp(r'^remote\s+\S+', multiLine: true).hasMatch(cleanConfig);

    if (RegExp(
      r'^\s*(up|down|route-up|ipchange|plugin|script-security|management|log|log-append|writepid|config)\s',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(cleanConfig)) {
      return 'Executable scripts, nested files and management directives are not supported.';
    }
    if (looksLikeOpenVpn &&
        RegExp(
          r'^\s*auth-user-pass\s*$',
          multiLine: true,
        ).hasMatch(cleanConfig)) {
      return 'Use a certificate-based profile or an inline auth-user-pass block.';
    }
    VpnProtocol proto = VpnProtocol.wireguard;
    if (looksLikeOpenVpn) {
      proto = VpnProtocol.openvpn;
    } else {
      final Map<String, Object?> check = await VpnBridge.instance
          .validateWireGuardConfig(cleanConfig);
      if (check['valid'] != true) {
        return check['error']?.toString() ??
            'Invalid WireGuard (.conf) or OpenVPN (.ovpn) format.';
      }
    }

    final VpnProfile created = VpnProfile(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty
          ? 'Custom VPN'
          : name.trim().substring(0, name.trim().length.clamp(0, 64)),
      countryLabel: countryLabel.trim().isEmpty
          ? 'Custom Country (${proto.name.toUpperCase()})'
          : countryLabel.trim(),
      configText: cleanConfig,
      flagEmoji: '🌐',
      protocol: proto,
    );

    _customProfiles = <VpnProfile>[created, ..._customProfiles];
    _selectedProfileId = created.id;
    notifyListeners();
    unawaited(_persistCustomProfiles());
    unawaited(_prefs.setString(_keySelectedProfileId, _selectedProfileId));
    return null;
  }

  Future<void> removeCustomProfile(String profileId) async {
    final bool wasSelected = _selectedProfileId == profileId;
    _customProfiles = _customProfiles
        .where((VpnProfile p) => p.id != profileId)
        .toList();
    if (wasSelected) {
      _selectedProfileId = defaultForeignUsId;
      unawaited(_prefs.setString(_keySelectedProfileId, _selectedProfileId));
      if (_isConnected) {
        await disconnect();
      }
    }
    notifyListeners();
    unawaited(_persistCustomProfiles());
  }

  Future<void> rotateFreeWarpIdentity() async {
    _cachedWarpConfig = '';
    notifyListeners();
    unawaited(_saveSecret(_keyWarpConfig, null));
    if (_isConnected && _selectedProfileId == builtInWarpId) {
      await reconnect();
    }
  }

  Future<void> toggleConnection() async {
    if (_isBusy) return;
    if (_isConnected) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> reconnect() async {
    await disconnect();
    await connect();
  }

  Future<bool> connect() async {
    if (_isBusy) return false;
    _isBusy = true;
    _errorMessage = null;
    _exitIp = null;
    _exitCountry = null;
    _rxBytes = 0;
    _txBytes = 0;
    final VpnProfile target = selectedProfile;
    _statusMessage = 'Connecting to ${target.name}';
    notifyListeners();

    if (target.protocol == VpnProtocol.openvpn) {
      return _connectOpenVpnProfile(target);
    }
    return _connectWireGuardProfile(target);
  }

  Future<bool> _connectOpenVpnProfile(VpnProfile target) async {
    try {
      _statsTimer?.cancel();
      // Tear down any active WireGuard tunnel in parallel with provisioning Attempt 0!
      Future<void>? wgStopFuture = VpnBridge.instance.disconnectVpn();

      for (int attempt = 0; attempt < 3; attempt++) {
        String configToUse = target.configText.trim();
        String? connectedHost;

        if (target.isBuiltInForeign) {
          _statusMessage = attempt == 0
              ? 'Connecting to ${target.name}'
              : 'Trying backup ${target.name} server (#${attempt + 1})';
          notifyListeners();

          final Future<Map<String, Object?>> provFuture = VpnBridge.instance
              .provisionForeignOpenVpnConfig(
                countryCode: target.countryCode,
                excludeHosts: _sessionExcludedHosts.toList(growable: false),
              );
          if (wgStopFuture != null) {
            await wgStopFuture;
            wgStopFuture = null;
          }
          final Map<String, Object?> provisioned = await provFuture;
          if (provisioned['ok'] != true ||
              (provisioned['configText']?.toString().trim().isEmpty ?? true)) {
            if (attempt == 0 && _sessionExcludedHosts.isNotEmpty) {
              _sessionExcludedHosts.clear();
              continue;
            }
            _isBusy = false;
            _statusMessage = null;
            _errorMessage =
                provisioned['error']?.toString() ??
                'Foreign servers busy. Please pick another country.';
            notifyListeners();
            return false;
          }
          configToUse = provisioned['configText']!.toString().trim();
          connectedHost = provisioned['serverHost']?.toString().trim();
        } else {
          if (wgStopFuture != null) {
            await wgStopFuture;
            wgStopFuture = null;
          }
          configToUse =
              await ovpn.OpenVPN.filteredConfig(configToUse) ?? configToUse;
        }

        // In unit/widget test mode (enableNativePolling == false), mark connected cleanly
        if (!enableNativePolling) {
          _activeEngineProtocol = VpnProtocol.openvpn;
          _isConnected = true;
          _isBusy = false;
          _statusMessage = null;
          await refreshExitIpInfo();
          onTunnelConnected?.call();
          notifyListeners();
          return true;
        }

        final ovpn.OpenVPN? engine = await _ensureOpenVpnEngine();
        if (engine == null) {
          _isBusy = false;
          _statusMessage = null;
          _errorMessage = 'OpenVPN engine unavailable on this device.';
          notifyListeners();
          return false;
        }

        _activeEngineProtocol = VpnProtocol.openvpn;
        _statusMessage = 'Connecting to ${target.name}';
        notifyListeners();

        final bool hasCert =
            configToUse.contains('<cert>') && configToUse.contains('<key>');
        final bool usesUserPass = RegExp(
          r'^\s*auth-user-pass(\s|$)',
          multiLine: true,
          caseSensitive: false,
        ).hasMatch(configToUse);

        final bool started = await engine.connect(
          configToUse,
          'Max Player VPN • ${target.name}',
          username: target.isBuiltInForeign && (usesUserPass || !hasCert)
              ? 'vpn'
              : null,
          password: target.isBuiltInForeign && (usesUserPass || !hasCert)
              ? 'vpn'
              : null,
          certIsRequired: hasCert,
          allowedPackages: _appOnly
              ? const <String>['com.hypertechlabs.maxplayer']
              : null,
        );

        if (!started) {
          _isBusy = false;
          _statusMessage = null;
          _errorMessage = 'VPN connection permission was declined.';
          notifyListeners();
          return false;
        }

        // Wait up to 16 seconds for tunnel handshake & route setup
        final bool established = await _waitForOpenVpnConnected(engine);
        if (established) {
          _isConnected = true;
          _isBusy = false;
          _statusMessage = null;
          unawaited(refreshExitIpInfo(allowDelayedRetry: true));
          onTunnelConnected?.call();
          notifyListeners();
          return true;
        }

        // Do not include native profile parser/engine logs in user errors.
        // Server stalled during TLS/auth -> exclude host and auto-try next live server!
        await engine.disconnect();
        if (connectedHost != null && connectedHost.isNotEmpty) {
          _sessionExcludedHosts.add(connectedHost);
        }
        if (!target.isBuiltInForeign) {
          break;
        }
      }

      _isConnected = false;
      _isBusy = false;
      _statusMessage = null;
      _errorMessage =
          'VPN handshake failed. Try another provider or check your configuration.';
      notifyListeners();
      return false;
    } catch (e) {
      _isConnected = false;
      _isBusy = false;
      _statusMessage = null;
      _errorMessage =
          'VPN connection failed. Check the profile and network, then retry.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> _waitForOpenVpnConnected(ovpn.OpenVPN engine) async {
    if (engine.currentStage == ovpn.VPNStage.connected) {
      return true;
    }
    final Completer<bool> completer = Completer<bool>();
    late final StreamSubscription<ovpn.VPNStage> sub;
    final Timer timeout = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    sub = engine.stageStream.listen((ovpn.VPNStage stage) {
      if (completer.isCompleted) return;
      if (stage == ovpn.VPNStage.connected) {
        completer.complete(true);
      } else if (stage == ovpn.VPNStage.denied ||
          stage == ovpn.VPNStage.error ||
          stage == ovpn.VPNStage.auth_failed) {
        completer.complete(false);
      }
    });

    final bool result = await completer.future;
    timeout.cancel();
    await sub.cancel();
    return result;
  }

  Future<bool> _connectWireGuardProfile(VpnProfile target) async {
    try {
      if (_openVpnEngine != null && _openVpnReady) {
        await _openVpnEngine!.disconnect();
      }
      String configToUse = target.configText;

      if (target.isBuiltInWarp && configToUse.trim().isEmpty) {
        _statusMessage = 'Preparing WireGuard key';
        notifyListeners();

        final Map<String, Object?> provisioned = await VpnBridge.instance
            .provisionFreeWarpConfig();
        if (provisioned['ok'] != true ||
            (provisioned['configText']?.toString().trim().isEmpty ?? true)) {
          _isBusy = false;
          _statusMessage = null;
          _errorMessage =
              provisioned['error']?.toString() ??
              'Could not register WARP key. Pick a Foreign Country server above.';
          notifyListeners();
          return false;
        }
        configToUse = provisioned['configText']!.toString().trim();
        _cachedWarpConfig = configToUse;
        unawaited(_saveSecret(_keyWarpConfig, _cachedWarpConfig));
      }

      _statusMessage = 'Starting WireGuard tunnel';
      notifyListeners();

      final Map<String, Object?> res = await VpnBridge.instance.connectVpn(
        configText: configToUse,
        profileName: target.name,
        appOnly: _appOnly,
      );

      final bool ok = res['ok'] == true && res['connected'] == true;
      if (!ok) {
        final String rawErr = res['error']?.toString() ?? '';
        _activeEngineProtocol = null;
        _isConnected = false;
        _isBusy = false;
        _statusMessage = null;
        _errorMessage = rawErr.isNotEmpty
            ? rawErr
            : 'Unable to connect WireGuard VPN';
        notifyListeners();
        return false;
      }

      final String? activeCfg = res['activeConfigText']?.toString().trim();
      if (target.isBuiltInWarp && activeCfg != null && activeCfg.isNotEmpty) {
        _cachedWarpConfig = activeCfg;
        unawaited(_saveSecret(_keyWarpConfig, _cachedWarpConfig));
      }

      _activeEngineProtocol = VpnProtocol.wireguard;
      _isConnected = true;
      _isBusy = false;
      _statusMessage = null;

      if (enableNativePolling) {
        _startWireGuardPolling();
      }
      await refreshExitIpInfo(allowDelayedRetry: enableNativePolling);
      onTunnelConnected?.call();
      notifyListeners();
      return true;
    } catch (e) {
      _isBusy = false;
      _isConnected = false;
      _statusMessage = null;
      _errorMessage =
          'VPN connection failed. Check the profile and network, then retry.';
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    _statsTimer?.cancel();
    if (_openVpnEngine != null && _openVpnReady) {
      await _openVpnEngine!.disconnect();
    }
    await VpnBridge.instance.disconnectVpn();

    _activeEngineProtocol = null;
    _isConnected = false;
    _isBusy = false;
    _statusMessage = null;
    _rxBytes = 0;
    _txBytes = 0;
    _exitIp = null;
    _exitCountry = null;
    notifyListeners();
  }

  Future<void> syncNativeStatus() async {
    final Map<String, Object?> st = await VpnBridge.instance.getVpnStatus();
    final bool wgUp = st['connected'] == true;
    if (wgUp) {
      _activeEngineProtocol = VpnProtocol.wireguard;
      _isConnected = true;
      _rxBytes = (st['rxBytes'] is num) ? (st['rxBytes']! as num).toInt() : 0;
      _txBytes = (st['txBytes'] is num) ? (st['txBytes']! as num).toInt() : 0;
      if (enableNativePolling) {
        _startWireGuardPolling();
        if (_exitIp == null) {
          unawaited(refreshExitIpInfo());
        }
      }
      notifyListeners();
    }
  }

  Future<void> refreshExitIpInfo({bool allowDelayedRetry = false}) async {
    final bool updated = await _fetchTraceOnce();
    if (!updated && allowDelayedRetry && _isConnected) {
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      if (_isConnected) {
        await _fetchTraceOnce();
      }
    }
  }

  Future<bool> _fetchTraceOnce() async {
    try {
      String bodyText = '';
      if (enableNativePolling) {
        // Open a brand-new socket with zero keep-alive reuse so it traverses tun0!
        final HttpClient freshClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5)
          ..idleTimeout = Duration.zero;
        try {
          final HttpClientRequest req = await freshClient.getUrl(
            Uri.parse('https://1.1.1.1/cdn-cgi/trace'),
          );
          final HttpClientResponse res = await req.close().timeout(
            const Duration(seconds: 6),
          );
          if (res.statusCode == 200) {
            bodyText = await res.transform(utf8.decoder).join();
          }
        } finally {
          freshClient.close(force: true);
        }
      } else {
        final http.Response resp = await _client
            .get(Uri.parse('https://1.1.1.1/cdn-cgi/trace'))
            .timeout(const Duration(seconds: 6));
        if (resp.statusCode == 200) {
          bodyText = resp.body;
        }
      }

      if (bodyText.isNotEmpty) {
        String? ip;
        String? loc;
        for (final String line in bodyText.split('\n')) {
          if (line.startsWith('ip=')) {
            ip = line.substring(3).trim();
          } else if (line.startsWith('loc=')) {
            loc = line.substring(4).trim();
          }
        }
        if (ip != null && ip.isNotEmpty) {
          _exitIp = ip;
          _exitCountry = loc;
          notifyListeners();
          return true;
        }
      }
    } catch (_) {
      // Non-fatal if tunnel routes are still settling.
    }
    return false;
  }

  void _startWireGuardPolling() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_activeEngineProtocol != VpnProtocol.wireguard) {
        _statsTimer?.cancel();
        return;
      }
      final Map<String, Object?> st = await VpnBridge.instance.getVpnStatus();
      final bool up = st['connected'] == true;
      _isConnected = up;
      _rxBytes = (st['rxBytes'] is num) ? (st['rxBytes']! as num).toInt() : 0;
      _txBytes = (st['txBytes'] is num) ? (st['txBytes']! as num).toInt() : 0;
      if (!up) {
        _statsTimer?.cancel();
      }
      notifyListeners();
    });
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final double kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final double mb = kb / 1024.0;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final double gb = mb / 1024.0;
    return '${gb.toStringAsFixed(2)} GB';
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _openVpnEngine?.dispose();
    _client.close();
    super.dispose();
  }
}
