import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/sync_contact.dart';
import 'package:localsend_app/pages/pending_sync_page.dart';
import 'package:localsend_app/pages/sync/contact_detail_page.dart';
import 'package:localsend_app/provider/sync/sync_contact_provider.dart';
import 'package:localsend_app/provider/sync/sync_session_provider.dart';
import 'package:localsend_app/widget/list_tile/custom_list_tile.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// WeChat-style entry point for the directory-sync flow.
///
/// Layout (top to bottom):
///   1. AppBar with the page title and a `待确认 N` chip on the right
///      (visible when any sync session has unresolved conflicts).
///   2. The "已配对" section — every contact the user has trusted at
///      least once. Tapping opens the 3-tab detail page.
///   3. The "附近" section — every other contact we have ever seen.
///      Tapping opens a one-shot trust dialog the first time; after
///      that it behaves like a paired contact.
///
/// Long-pressing any row opens a context menu with edit / delete /
/// toggle-trust / view-fingerprint. The trust dialog can also be
/// re-opened from the menu at any time.
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  /// Search filter (matches alias, case-insensitive).
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final session = context.watch(syncSessionProvider);
    final pendingCount = session == null
        ? 0
        : (session.plan?.conflicts.length ?? 0) - session.conflictDecisions.length;
    final allContacts = context.watch(syncContactProvider);

    final filtered = _filter.isEmpty
        ? allContacts
        : allContacts.where((c) => c.alias.toLowerCase().contains(_filter.toLowerCase())).toList(growable: false);
    final paired = filtered.where((c) => c.trusted).toList(growable: false);
    final nearby = filtered.where((c) => !c.trusted).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.contactsPage.title),
        actions: [
          if (pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () async {
                  await context.push(() => const PendingSyncPage());
                },
                icon: const Icon(Icons.folder_open),
                label: Text(t.contactsPage.pending(count: pendingCount)),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t.contactsPage.searchHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(hadContacts: allContacts.isNotEmpty)
                : ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      if (paired.isNotEmpty) ...[
                        _SectionHeader(label: t.contactsPage.sections.paired, count: paired.length),
                        ...paired.map((c) => _ContactRow(contact: c, onOpen: () => _openContact(c))),
                        const SizedBox(height: 16),
                      ],
                      if (nearby.isNotEmpty) ...[
                        _SectionHeader(label: t.contactsPage.sections.nearby, count: nearby.length),
                        ...nearby.map((c) => _ContactRow(contact: c, onOpen: () => _openContact(c))),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openContact(SyncContact contact) async {
    if (!contact.trusted) {
      // First-touch: show the trust dialog before opening anything.
      final ok = await _showTrustDialog(contact);
      if (ok != true) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    await context.push(() => ContactDetailPage(fingerprint: contact.id));
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;

  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 8),
          Text('($count)', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hadContacts;
  const _EmptyState({required this.hadContacts});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.contacts_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              hadContacts ? t.contactsPage.empty.filtered : t.contactsPage.empty.none,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final SyncContact contact;
  final Future<void> Function() onOpen;

  const _ContactRow({required this.contact, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (contact.ip != null && contact.port != null) '${contact.ip}:${contact.port}',
      if (contact.trusted) t.contactsPage.trusted else t.contactsPage.untrusted,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onLongPress: () => _showContextMenu(context),
        child: CustomListTile(
          icon: Icon(contact.trusted ? Icons.person : Icons.person_outline, size: 36),
          title: Text(contact.alias, maxLines: 1, overflow: TextOverflow.ellipsis),
          subTitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
          onTap: onOpen,
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) async {
    final action = await showModalBottomSheet<_ContactAction>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(t.contactsPage.menu.rename),
              onTap: () => Navigator.of(context).pop(_ContactAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: Text(t.contactsPage.menu.fingerprint),
              onTap: () => Navigator.of(context).pop(_ContactAction.viewFingerprint),
            ),
            ListTile(
              leading: Icon(contact.trusted ? Icons.lock_open : Icons.lock_outline),
              title: Text(contact.trusted ? t.contactsPage.menu.untrust : t.contactsPage.menu.trust),
              onTap: () => Navigator.of(context).pop(contact.trusted ? _ContactAction.untrust : _ContactAction.trust),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(t.contactsPage.menu.delete, style: const TextStyle(color: Colors.red)),
              onTap: () => Navigator.of(context).pop(_ContactAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) {
      return;
    }
    final ref = context.ref;
    switch (action) {
      case _ContactAction.rename:
        final newName = await _promptAlias(context, contact.alias);
        if (newName != null && newName.isNotEmpty && context.mounted) {
          await ref.redux(syncContactProvider).dispatchAsync(
                RenameSyncContactAction(fingerprint: contact.id, alias: newName),
              );
        }
        break;
      case _ContactAction.viewFingerprint:
        await _showFingerprintDialog(context, contact);
        break;
      case _ContactAction.trust:
        final ok = await _showTrustDialog(contact);
        if (ok == true && context.mounted) {
          await ref.redux(syncContactProvider).dispatchAsync(
                TrustSyncContactAction(fingerprint: contact.id, trusted: true),
              );
        }
        break;
      case _ContactAction.untrust:
        await ref.redux(syncContactProvider).dispatchAsync(
              TrustSyncContactAction(fingerprint: contact.id, trusted: false),
            );
        break;
      case _ContactAction.delete:
        final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(t.contactsPage.confirmDeleteTitle),
                content: Text(t.contactsPage.confirmDeleteBody(alias: contact.alias)),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.general.cancel)),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(t.general.delete, style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ) ??
            false;
        if (ok && context.mounted) {
          await ref.redux(syncContactProvider).dispatchAsync(RemoveSyncContactAction(contact.id));
        }
        break;
    }
  }
}

enum _ContactAction { rename, viewFingerprint, trust, untrust, delete }

/// Shows the fingerprint and asks the user to confirm trust. Returns
/// `true` only when the user explicitly tapped "Trust". Returns
/// `false` (or null) on dismiss.
Future<bool?> _showTrustDialog(SyncContact contact) async {
  final context = WidgetsBinding.instance.rootElement;
  if (context == null) {
    return null;
  }
  // Re-use the root navigator. In practice this is always a MaterialApp
  // ancestor; tests that bypass it should not call this helper.
  final state = context.findAncestorStateOfType<NavigatorState>();
  final navigator = state;
  if (navigator == null) {
    return null;
  }
  return showDialog<bool>(
    context: navigator.context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t.contactsPage.trustDialog.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.contactsPage.trustDialog.body(alias: contact.alias)),
          const SizedBox(height: 12),
          SelectableText(
            contact.fingerprintDisplay,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(t.general.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(t.contactsPage.trustDialog.confirm),
        ),
      ],
    ),
  );
}

Future<void> _showFingerprintDialog(BuildContext context, SyncContact contact) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(contact.alias),
      content: SelectableText(
        contact.fingerprintDisplay,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: contact.fingerprintDisplay));
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          },
          child: Text(t.general.copy),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(t.general.close),
        ),
      ],
    ),
  );
}

Future<String?> _promptAlias(BuildContext context, String initial) async {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t.contactsPage.renameDialog.title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: t.contactsPage.renameDialog.label),
        onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(t.general.cancel)),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          child: Text(t.general.save),
        ),
      ],
    ),
  );
}

/// Helper used by tests and other widgets that want to surface the
/// "view fingerprint" entry-point without going through the full
/// long-press flow.
@visibleForTesting
Future<void> showContactFingerprintDialog(BuildContext context, SyncContact contact) =>
    _showFingerprintDialog(context, contact);
