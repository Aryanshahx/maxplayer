import 'package:flutter/material.dart';
import '../../utils/app_language.dart';
import 'vpn_controller.dart';

/// One app-scoped controller: Back does not silently tear down a user-started VPN.
class VpnEntryScreen extends StatefulWidget {
  const VpnEntryScreen({super.key, this.controller});
  final VpnController? controller;
  @override
  State<VpnEntryScreen> createState() => _VpnEntryScreenState();
}

class _VpnEntryScreenState extends State<VpnEntryScreen> {
  static Future<VpnController>? _session;
  bool _loaded = false;
  VpnController? _vpn;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _vpn = widget.controller ?? await (_session ??= VpnController.create());
    } catch (_) {
      _session = null;
      _error = 'VPN is unavailable on this device. Please try again.';
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final vpn = _vpn;
    return Scaffold(
      appBar: AppBar(title: const LText('VPN')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : vpn == null
          ? Center(child: Text(_error ?? 'VPN unavailable'))
          : _VpnControls(vpn: vpn),
    );
  }
}

class _VpnControls extends StatefulWidget {
  const _VpnControls({required this.vpn});
  final VpnController vpn;
  @override
  State<_VpnControls> createState() => _VpnControlsState();
}

class _VpnControlsState extends State<_VpnControls> {
  String _query = '';
  Future<void> _import() async {
    final name = TextEditingController();
    final config = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const LText('Import VPN profile'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Profile name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: config,
                    minLines: 5,
                    maxLines: 10,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'WireGuard .conf or OpenVPN .ovpn',
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const LText('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final result = await widget.vpn.addCustomProfile(
                  name: name.text,
                  countryLabel: 'Custom profile',
                  configText: config.text,
                );
                if (!c.mounted) return;
                if (result == null) {
                  Navigator.pop(c);
                } else {
                  setDialogState(() => error = result);
                }
              },
              child: const LText('Save'),
            ),
          ],
        ),
      ),
    );
    // The dialog's reverse transition may still reference its controllers.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    config.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.vpn,
    builder: (context, _) {
      final vpn = widget.vpn;
      final profiles =
          [
                vpn.builtInWarpProfile,
                ...vpn.foreignProfiles,
                ...vpn.customProfiles,
              ]
              .where(
                (p) => '${p.name} ${p.countryCode} ${p.countryLabel}'
                    .toLowerCase()
                    .contains(_query),
              )
              .toList();
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        vpn.isBusy
                            ? (vpn.statusMessage ?? 'Connecting')
                            : vpn.isConnected
                            ? 'Connected'
                            : 'Disconnected',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(vpn.selectedProfile.name),
                      if (vpn.exitIp != null)
                        Text(
                          'Exit: ${vpn.exitIp} • ${vpn.exitCountry ?? "Unknown"}',
                        ),
                      if (vpn.isConnected)
                        Text(
                          'Received ${VpnController.formatBytes(vpn.rxBytes)} • Sent ${VpnController.formatBytes(vpn.txBytes)}',
                        ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: vpn.isBusy ? null : vpn.toggleConnection,
                        icon: Icon(
                          vpn.isConnected
                              ? Icons.power_settings_new
                              : Icons.vpn_lock_outlined,
                        ),
                        label: Text(vpn.isConnected ? 'Disconnect' : 'Connect'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const LText('Max Player only'),
                        value: vpn.appOnly,
                        onChanged: vpn.isBusy ? null : vpn.setAppOnly,
                      ),
                      if (vpn.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            vpn.errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: vpn.isBusy ? null : _import,
                    icon: const Icon(Icons.add),
                    label: const LText('Import profile'),
                  ),
                  OutlinedButton.icon(
                    onPressed: vpn.isRefreshingServers || vpn.isBusy
                        ? null
                        : vpn.refreshLiveForeignServers,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      vpn.isRefreshingServers
                          ? 'Refreshing'
                          : 'Refresh countries',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: const InputDecoration(
                  labelText: 'Search VPN profiles',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              for (final p in profiles)
                Card(
                  child: ListTile(
                    leading: Text(p.flagEmoji),
                    title: Text(p.name),
                    subtitle: Text(p.countryLabel),
                    selected: vpn.selectedProfileId == p.id,
                    onTap: vpn.isBusy ? null : () => vpn.selectProfile(p.id),
                    trailing:
                        vpn.customProfiles.any((custom) => custom.id == p.id)
                        ? IconButton(
                            tooltip: 'Delete profile',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: vpn.isBusy
                                ? null
                                : () => vpn.removeCustomProfile(p.id),
                          )
                        : vpn.selectedProfileId == p.id
                        ? const Icon(Icons.check_circle_outline)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
