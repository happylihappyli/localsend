import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/sync_contact.dart';
import 'package:localsend_app/pages/browse_shares_page.dart';
import 'package:localsend_app/provider/sync/sync_contact_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Three-tab detail view for a single paired contact.
///
/// Tab 1 ("Chat") is intentionally a placeholder — chat is a v2
/// feature and the design doc says to ship without it. The tab
/// exists so the navigation matches the WeChat reference and the
/// slots won't shift later.
///
/// Tab 2 ("Send") links to the regular send flow. v1 uses the
/// `SendTab` and lets the user pick this contact from the device
/// list; once the sync_contact is also a favorite_device the flow
/// shortens to a single tap.
///
/// Tab 3 ("Browse shared") is the directory-sync entry point. v1
/// delegates to the existing [BrowseSharesPage]; once the contact
/// is the only device exposing shares, this can be inlined.
class ContactDetailPage extends StatelessWidget {
  final String fingerprint;

  const ContactDetailPage({required this.fingerprint, super.key});

  @override
  Widget build(BuildContext context) {
    final contact = context.watch(syncContactProvider.select((list) => list.firstWhere(
          (c) => c.id == fingerprint,
          orElse: () => const SyncContact(id: '', alias: ''),
        )));
    if (contact.id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(t.contactDetailPage.title)),
        body: Center(child: Text(t.contactDetailPage.notFound)),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(contact.alias),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.chat_bubble_outline), text: t.contactDetailPage.tabs.chat),
              Tab(icon: const Icon(Icons.send), text: t.contactDetailPage.tabs.send),
              Tab(icon: const Icon(Icons.folder_shared), text: t.contactDetailPage.tabs.browse),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ChatPlaceholder(contact: contact),
            _SendTabHint(contact: contact),
            _BrowseTab(contact: contact),
          ],
        ),
      ),
    );
  }
}

class _ChatPlaceholder extends StatelessWidget {
  final SyncContact contact;
  const _ChatPlaceholder({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              t.contactDetailPage.chatPlaceholder.title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              t.contactDetailPage.chatPlaceholder.body,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendTabHint extends StatelessWidget {
  final SyncContact contact;
  const _SendTabHint({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.send, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              t.contactDetailPage.sendHint.title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              t.contactDetailPage.sendHint.body(alias: contact.alias),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseTab extends StatelessWidget {
  final SyncContact contact;
  const _BrowseTab({required this.contact});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_shared, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              t.contactDetailPage.browseHint.title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              t.contactDetailPage.browseHint.body(alias: contact.alias),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                // v1 delegates to the global BrowseSharesPage; the
                // contact is just one row in the list. Once the
                // contact is the only device offering a share this
                // button can dispatch a focused browse action that
                // opens the tree directly.
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BrowseSharesPage()));
              },
              icon: const Icon(Icons.list),
              label: Text(t.contactDetailPage.browseHint.action),
            ),
          ],
        ),
      ),
    );
  }
}
