import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/sync_share.dart';
import 'package:localsend_app/util/native/pick_directory_path.dart';

/// What the user did in the [ShareDirectoryDialog].
///
/// The dialog is presentation-only: the page that opened it inspects the
/// result and dispatches the right [Redux] action itself.
sealed class ShareDialogResult {
  const ShareDialogResult();
}

/// The user pressed "Save". [share] is the next state of the entry:
/// when [existing] was non-null, [share] is an updated copy of it; when
/// it was null, [share] is a brand-new share with a fresh id.
class ShareDialogSaved extends ShareDialogResult {
  final SyncShare share;
  const ShareDialogSaved(this.share);
}

/// The user pressed "Remove" on an existing entry. [id] is the share id
/// to remove.
class ShareDialogRemoved extends ShareDialogResult {
  final String id;
  const ShareDialogRemoved(this.id);
}

/// The user dismissed the dialog (Cancel, ESC, barrier tap). Nothing to do.
class ShareDialogCancelled extends ShareDialogResult {
  const ShareDialogCancelled();
}

/// Modal dialog for creating or editing a [SyncShare]. When [existing] is
/// non-null, the dialog is in "edit" mode and exposes a "Remove" button
/// in addition to "Save". When null, the dialog is in "add" mode.
class ShareDirectoryDialog extends StatefulWidget {
  final SyncShare? existing;

  const ShareDirectoryDialog({this.existing, super.key});

  static Future<ShareDialogResult?> show(BuildContext context, {SyncShare? existing}) {
    return showDialog<ShareDialogResult>(
      context: context,
      builder: (_) => ShareDirectoryDialog(existing: existing),
    );
  }

  @override
  State<ShareDirectoryDialog> createState() => _ShareDirectoryDialogState();
}

class _ShareDirectoryDialogState extends State<ShareDirectoryDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _rootController;
  late final TextEditingController _excludesController;
  String? _nameError;
  String? _rootError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _rootController = TextEditingController(text: widget.existing?.root ?? '');
    _excludesController = TextEditingController(
      text: (widget.existing?.excludes ?? const []).join('\n'),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rootController.dispose();
    _excludesController.dispose();
    super.dispose();
  }

  Future<void> _pickRoot() async {
    final path = await pickDirectoryPath();
    if (path == null) {
      return;
    }
    setState(() {
      _rootController.text = path;
      _rootError = null;
    });
  }

  List<String> _parseExcludes() {
    return _excludesController.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  void _onSave() {
    final name = _nameController.text.trim();
    final root = _rootController.text.trim();
    var hasError = false;
    if (name.isEmpty) {
      setState(() => _nameError = t.settingsTab.shareDialog.nameRequired);
      hasError = true;
    }
    if (root.isEmpty) {
      setState(() => _rootError = t.settingsTab.shareDialog.rootRequired);
      hasError = true;
    }
    if (hasError) {
      return;
    }
    final next = (widget.existing ??
            SyncShare.create(name: name, root: root, excludes: _parseExcludes()))
        .copyWith(name: name, root: root, excludes: _parseExcludes());
    Navigator.of(context).pop(ShareDialogSaved(next));
  }

  void _onRemove() {
    Navigator.of(context).pop(ShareDialogRemoved(widget.existing!.id));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? t.settingsTab.shareDialog.editTitle : t.settingsTab.shareDialog.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: t.settingsTab.shareDialog.name,
                hintText: t.settingsTab.shareDialog.nameHint,
                errorText: _nameError,
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _rootController,
                    decoration: InputDecoration(
                      labelText: t.settingsTab.shareDialog.root,
                      hintText: t.settingsTab.shareDialog.rootPlaceholder,
                      errorText: _rootError,
                    ),
                    readOnly: true,
                    maxLines: 2,
                    minLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: _pickRoot,
                    icon: const Icon(Icons.folder_open),
                    label: Text(t.settingsTab.shareDialog.pick),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(t.settingsTab.shareDialog.excludes, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(t.settingsTab.shareDialog.excludesHint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: _excludesController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 6,
              minLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        if (_isEdit)
          TextButton(
            onPressed: _onRemove,
            child: Text(
              t.settingsTab.shareDialog.remove,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(const ShareDialogCancelled()),
          child: Text(t.general.cancel),
        ),
        FilledButton(onPressed: _onSave, child: Text(t.settingsTab.shareDialog.save)),
      ],
    );
  }
}
