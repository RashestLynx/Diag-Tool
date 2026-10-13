import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'recovery.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, required this.recovery});
  final Recovery recovery;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  late String _platform = widget.recovery.platforms.first;

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recovery;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Get back into your account', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('The way back to a locked phone is to recover the ACCOUNT - that releases the '
            'device and its backups. These are the official, first-party steps.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        _ownershipNote(context),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: [
            for (final p in r.platforms)
              ButtonSegment(value: p, label: Text(recoveryPlatformLabels[p] ?? p)),
          ],
          selected: {_platform},
          onSelectionChanged: (s) => setState(() => _platform = s.first),
        ),
        const SizedBox(height: 16),
        _servicesCard(context),
        const SizedBox(height: 12),
        _linesCard(context, 'Step-by-step recovery', Icons.checklist, r.checklists[_platform] ?? []),
        const SizedBox(height: 12),
        _linesCard(context, 'Where your backups live', Icons.cloud_outlined, r.backups[_platform] ?? []),
        const SizedBox(height: 12),
        _linesCard(context, 'Copy data off an unlocked device', Icons.usb, r.connect[_platform] ?? [],
            footer: 'This needs the device UNLOCKED - that on-device approval is the point. '
                'A locked phone can’t grant it.'),
        const SizedBox(height: 12),
        _ownershipCard(context),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _ownershipNote(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.verified_user_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This is for a device you own. Recovery verifies ownership through Apple/Samsung/'
                'Google - it doesn’t remove someone else’s lock.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _servicesCard(BuildContext context) {
    final services = widget.recovery.services[_platform] ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.open_in_new),
              const SizedBox(width: 8),
              Text('Official services', style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            Text('Recover the account first; it unlocks the device and backups.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            ...services.map((s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(s.name),
                  subtitle: Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(s.url),
                )),
          ],
        ),
      ),
    );
  }

  Widget _linesCard(BuildContext context, String title, IconData icon, List<String> lines,
      {String? footer}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 12),
            ...lines.map((line) => _StepLine(line, onOpen: _open)),
            if (footer != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(footer, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ownershipCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.description_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Ownership-proof sheet', style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Fill in what you know and hand it to Apple/Samsung support to help them '
                'verify you own the device.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => _openOwnershipSheet(context),
              icon: const Icon(Icons.edit_document),
              label: const Text('Build my ownership sheet'),
            ),
          ],
        ),
      ),
    );
  }

  void _openOwnershipSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _OwnershipSheet(fields: widget.recovery.ownershipFields),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine(this.text, {required this.onOpen});
  final String text;
  final Future<void> Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Pull any URL out so it can be tapped.
    final match = RegExp(r'https?://[^\s]+').firstMatch(text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5, right: 8),
            child: Icon(Icons.arrow_right, size: 18),
          ),
          Expanded(
            child: match == null
                ? Text(text)
                : InkWell(
                    onTap: () => onOpen(match.group(0)!),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: text.substring(0, match.start)),
                      TextSpan(
                        text: match.group(0),
                        style: TextStyle(
                            color: scheme.primary, decoration: TextDecoration.underline),
                      ),
                      TextSpan(text: text.substring(match.end)),
                    ])),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OwnershipSheet extends StatefulWidget {
  const _OwnershipSheet({required this.fields});
  final List<String> fields;

  @override
  State<_OwnershipSheet> createState() => _OwnershipSheetState();
}

class _OwnershipSheetState extends State<_OwnershipSheet> {
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.fields) f: TextEditingController(),
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _buildSheet() {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final b = StringBuffer()
      ..writeln('DEVICE OWNERSHIP SHEET')
      ..writeln('Prepared: $date')
      ..writeln('(Hand this to Apple/Samsung support to help verify you own the device.)')
      ..writeln();
    for (final f in widget.fields) {
      final v = _controllers[f]!.text.trim();
      b.writeln('  ${f.padRight(26)}: ${v.isEmpty ? '____________________' : v}');
    }
    b
      ..writeln()
      ..writeln('  Proof of purchase (receipt/box) : [ ] attached  [ ] to find')
      ..writeln('  Government photo ID             : [ ] ready');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Ownership-proof sheet', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 12),
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _controllers[f],
                decoration: InputDecoration(
                  labelText: f,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _buildSheet()));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Ownership sheet copied to clipboard')));
              }
            },
            icon: const Icon(Icons.copy_all),
            label: const Text('Copy sheet to clipboard'),
          ),
        ],
      ),
    );
  }
}
