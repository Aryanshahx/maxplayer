import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../vault/encrypted_vault.dart';
import '../vault/dpapi.dart';
import '../cloud_import.dart' show ImportCancellation;
import '../local_media_index.dart' show mediaSize;

class PrivateVaultGate extends StatelessWidget {
  final bool creating, busy, acknowledged;
  final TextEditingController password, repeat;
  final String? error;
  final ValueChanged<bool> onAcknowledge;
  final VoidCallback onSubmit, onRecovery;
  const PrivateVaultGate(
      {super.key,
      required this.creating,
      required this.busy,
      required this.acknowledged,
      required this.password,
      required this.repeat,
      required this.onAcknowledge,
      required this.onSubmit,
      required this.onRecovery,
      this.error});
  @override
  Widget build(BuildContext context) => Center(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline, size: 56, color: Colors.white),
                const SizedBox(height: 14),
                Text(creating ? 'Create a vault password' : 'Private folder',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                    creating
                        ? 'Windows uses encrypted copies and a 12–128 character password, plus this Windows user account. Unlike Android’s app-private folder, a normal PC folder is not private.'
                        : 'Enter your password to decrypt the file list. The original Windows user account is also required.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13, height: 1.4)),
                const SizedBox(height: 18),
                TextField(
                    controller: password,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    enabled: !busy,
                    maxLength: 128,
                    decoration: InputDecoration(
                        labelText: creating
                            ? 'New password (at least 12 characters)'
                            : 'Password',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)))),
                if (creating) ...[
                  const SizedBox(height: 10),
                  TextField(
                      controller: repeat,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      enabled: !busy,
                      maxLength: 128,
                      decoration: InputDecoration(
                          labelText: 'Repeat password',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)))),
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: acknowledged,
                      onChanged: busy
                          ? null
                          : (value) => onAcknowledge(value ?? false),
                      title: const Text(
                          'I understand originals remain outside the vault and there is no password recovery.',
                          style: TextStyle(fontSize: 12.5)))
                ],
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13))
                ],
                const SizedBox(height: 18),
                SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black),
                        onPressed:
                            busy || creating && !acknowledged ? null : onSubmit,
                        icon: Icon(creating ? Icons.check : Icons.lock_open),
                        label: Text(creating ? 'Create & open' : 'Unlock'))),
                if (busy)
                  const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(minHeight: 2)),
                TextButton(
                    onPressed: busy ? null : onRecovery,
                    child: const Text('Recovery limits & data safety')),
                const Text(
                    'Deleting the app’s vault data/key, losing this Windows account’s protection or forgetting the password can make encrypted copies unrecoverable. Keep your own protected backups.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.amberAccent,
                        fontSize: 11.5,
                        height: 1.4)),
              ]))));
}

class DesktopPrivateSpaceScreen extends StatefulWidget {
  const DesktopPrivateSpaceScreen({super.key});
  @override
  State<DesktopPrivateSpaceScreen> createState() =>
      _DesktopPrivateSpaceScreenState();
}

class _DesktopPrivateSpaceScreenState extends State<DesktopPrivateSpaceScreen>
    with WidgetsBindingObserver {
  EncryptedVault? vault;
  final password = TextEditingController(), repeat = TextEditingController();
  bool creating = true, loading = true, busy = false, acknowledged = false;
  String? error;
  VaultListing listing = const VaultListing([], 0);
  ImportCancellation? cancellation;
  int done = 0, total = 0;
  int lockGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    boot();
  }

  Future<void> boot() async {
    if (!Platform.isWindows) {
      setState(() {
        loading = false;
        error =
            'Private Space requires Windows user-account protection. No insecure fallback is enabled.';
      });
      return;
    }
    try {
      final support = await getApplicationSupportDirectory();
      final store = EncryptedVault(
          Directory('${support.path}/private_space_v1'),
          WindowsDpapiProtector());
      final exists = await store.exists();
      if (mounted) {
        setState(() {
          vault = store;
          creating = !exists;
          loading = false;
        });
      } else {
        store.lock();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error =
              'Could not open vault storage. Existing encrypted copies have not been deleted.';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ([
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached
    ].contains(state)) {
      lock();
    }
  }

  void lock() {
    lockGeneration++;
    cancellation?.cancel();
    vault?.lock();
    password.clear();
    repeat.clear();
    if (mounted) {
      setState(() {
        listing = const VaultListing([], 0);
      });
    }
  }

  void recovery() {
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                backgroundColor: const Color(0xff1b1b24),
                title: const Text('Recovery limits'),
                scrollable: true,
                content: const Text(
                    'There is no password-reset bypass. The encrypted key also depends on Windows CurrentUser DPAPI; copying the vault to a different account does not guarantee recovery. Do not reset/delete its key file or setup lock to try to unlock existing media.\n\nImports are encrypted copies. Originals are not hidden or deleted. Export creates an unencrypted file wherever you explicitly save it; protect that copy yourself.\n\nThe implementation is experimental and has not had a security audit or native Windows recovery verification. It does not protect against malware running as you, a compromised unlocked PC, screenshots or operating-system paging. Keep tested backups before trusting it with irreplaceable data.',
                    style: TextStyle(fontSize: 13, height: 1.5)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'))
                ]));
  }

  Future<void> submit() async {
    final store = vault;
    if (store == null || busy) return;
    final generation = lockGeneration;
    final value = password.text;
    if (creating && value != repeat.text) {
      setState(() => error = 'Passwords do not match.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    password.clear();
    repeat.clear();
    try {
      if (creating) {
        await store.create(value);
      } else {
        await store.unlock(value);
      }
      if (!mounted || generation != lockGeneration) {
        store.lock();
        return;
      }
      final items = await store.list();
      if (mounted && store.unlocked) {
        setState(() {
          creating = false;
          listing = items;
        });
      } else {
        store.lock();
      }
    } catch (_) {
      store.lock();
      if (mounted) {
        setState(() => error =
            'Could not open the vault. Check the password, original Windows account and key files. Existing encrypted data was not reset.');
      }
    } finally {
      final hasKey = await store.exists();
      if (mounted) {
        setState(() {
          busy = false;
          creating = !hasKey;
        });
      }
    }
  }

  void progress(int copied, int bytes) {
    if (mounted) {
      setState(() {
        done = copied;
        total = bytes;
      });
    }
  }

  Future<void> importCopy() async {
    final store = vault;
    if (store == null || !store.unlocked || busy) return;
    setState(() {
      busy = true;
      error = null;
      done = 0;
      total = 0;
    });
    try {
      final picked = await openFile(acceptedTypeGroups: [
        const XTypeGroup(label: 'Videos', extensions: [
          'mp4',
          'mkv',
          'avi',
          'mov',
          'webm',
          'm4v',
          'ts',
          'wmv'
        ])
      ]);
      if (picked == null || !mounted) return;
      if (!store.unlocked) throw StateError('Vault locked');
      final token = ImportCancellation();
      cancellation = token;
      await store.importCopy(File(picked.path),
          cancellation: token, onProgress: progress);
      final items = await store.list();
      if (mounted && store.unlocked) setState(() => listing = items);
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Import stopped or failed. The original file was not deleted. Incomplete encrypted copies are cleaned up where possible.');
      }
    } finally {
      cancellation = null;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exportCopy(VaultEntry entry) async {
    final store = vault;
    if (store == null || !store.unlocked || busy) return;
    setState(() {
      busy = true;
      error = null;
      done = 0;
      total = 0;
    });
    try {
      final target = await getSaveLocation(suggestedName: entry.name);
      if (target == null || !mounted) return;
      if (!store.unlocked) throw StateError('Vault locked');
      final token = ImportCancellation();
      cancellation = token;
      await store.exportCopy(entry.id, File(target.path),
          cancellation: token, onProgress: progress);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Unencrypted copy saved. Encrypted original kept in vault.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Export stopped or failed. Choose a new filename; existing files are not overwritten. Missing/tampered encrypted data cannot be exported.');
      }
    } finally {
      cancellation = null;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(VaultEntry entry) async {
    final store = vault;
    if (store == null || !store.unlocked || busy) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Delete encrypted copy?'),
                content: const Text(
                    'This permanently deletes only this vault copy. It does not delete or restore your original file outside the vault.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete vault copy'))
                ]));
    if (confirmed != true || !mounted || !store.unlocked) return;
    setState(() => busy = true);
    try {
      await store.deleteEntry(entry.id);
      final items = await store.list();
      if (mounted && store.unlocked) setState(() => listing = items);
    } catch (_) {
      if (mounted) {
        setState(() => error =
            'Could not delete the vault copy. No outside original was changed.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cancellation?.cancel();
    vault?.lock();
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opened = vault?.unlocked == true;
    return Scaffold(
        backgroundColor: const Color(0xff14141c),
        appBar: AppBar(
            backgroundColor: const Color(0xff14141c),
            title: const Text('Private Space'),
            actions: [
              if (opened)
                IconButton(
                    tooltip: 'Lock Private Space',
                    onPressed: lock,
                    icon: const Icon(Icons.lock_outline)),
              IconButton(
                  tooltip: 'Recovery limits & data safety',
                  onPressed: recovery,
                  icon: const Icon(Icons.info_outline))
            ]),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : vault == null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(error ?? 'Vault unavailable',
                            textAlign: TextAlign.center)))
                : !opened
                    ? PrivateVaultGate(
                        creating: creating,
                        busy: busy,
                        acknowledged: acknowledged,
                        password: password,
                        repeat: repeat,
                        onAcknowledge: (v) => setState(() => acknowledged = v),
                        onSubmit: submit,
                        onRecovery: recovery,
                        error: error)
                    : Column(children: [
                        const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                                'Experimental encrypted copies · originals remain outside the vault. No plaintext thumbnails, library history or recommendations are generated here. Playback integration is not yet enabled; Export makes an explicitly unencrypted copy.',
                                style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 12,
                                    height: 1.5))),
                        if (busy) ...[
                          LinearProgressIndicator(
                              value: total > 0
                                  ? (done / total).clamp(0, 1)
                                  : null),
                          Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                  '${mediaSize(done)} of ${mediaSize(total)}',
                                  style: const TextStyle(fontSize: 12))),
                          if (cancellation != null)
                            TextButton(
                                onPressed: () => cancellation?.cancel(),
                                child: const Text('Cancel operation'))
                        ],
                        if (error != null)
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(error!,
                                  style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 12.5))),
                        if (listing.unreadable > 0)
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                  '${listing.unreadable} encrypted entries could not be authenticated. They have not been deleted.',
                                  style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 12.5))),
                        Expanded(
                            child: listing.entries.isEmpty
                                ? const Center(
                                    child: Text('No encrypted videos yet.',
                                        style:
                                            TextStyle(color: Colors.white54)))
                                : ListView.builder(
                                    padding: const EdgeInsets.all(14),
                                    itemCount: listing.entries.length,
                                    itemBuilder: (context, i) {
                                      final entry = listing.entries[i];
                                      return Card(
                                          child: ListTile(
                                              leading: const Icon(
                                                  Icons.lock_rounded,
                                                  color: Colors.white54),
                                              title: Text(entry.name,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              subtitle: Text(
                                                  '${mediaSize(entry.size)} · encrypted copy',
                                                  style: const TextStyle(
                                                      color: Colors.white38,
                                                      fontSize: 12)),
                                              trailing: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                        tooltip:
                                                            'Export unencrypted copy (new filename)',
                                                        onPressed: busy
                                                            ? null
                                                            : () => exportCopy(
                                                                entry),
                                                        icon: const Icon(Icons
                                                            .save_alt_rounded)),
                                                    IconButton(
                                                        tooltip:
                                                            'Delete encrypted copy',
                                                        onPressed: busy
                                                            ? null
                                                            : () =>
                                                                remove(entry),
                                                        icon: const Icon(Icons
                                                            .delete_outline))
                                                  ])));
                                    })),
                        SafeArea(
                            top: false,
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                        onPressed: busy ? null : importCopy,
                                        icon: const Icon(Icons.add),
                                        label: const Text(
                                            'Add encrypted copy (keep original)'))))),
                      ]));
  }
}
