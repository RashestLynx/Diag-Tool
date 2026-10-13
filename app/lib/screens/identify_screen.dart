import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../identify.dart';
import '../widgets.dart';

class IdentifyScreen extends StatefulWidget {
  const IdentifyScreen({super.key});

  @override
  State<IdentifyScreen> createState() => _IdentifyScreenState();
}

class _IdentifyScreenState extends State<IdentifyScreen> {
  final _imei = TextEditingController();
  final _serial = TextEditingController();
  ImeiInfo? _imeiInfo;
  SerialInfo? _serialInfo;

  @override
  void dispose() {
    _imei.dispose();
    _serial.dispose();
    super.dispose();
  }

  void _check() {
    FocusScope.of(context).unfocus();
    setState(() {
      _imeiInfo = _imei.text.trim().isEmpty ? null : ImeiInfo.parse(_imei.text);
      _serialInfo = _serial.text.trim().isEmpty ? null : SerialInfo(_serial.text);
    });
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Identify a device', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Check an IMEI or serial number. On a phone, dial *#06# to show its IMEI.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextField(
          controller: _imei,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(15)],
          decoration: InputDecoration(
            labelText: 'IMEI (15 digits)',
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _serial,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Serial number',
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _check, icon: const Icon(Icons.search), label: const Text('Check')),
        const SizedBox(height: 16),
        if (_imeiInfo != null) _imeiCard(context, _imeiInfo!),
        if (_serialInfo != null) _serialCard(context, _serialInfo!),
      ],
    );
  }

  Widget _imeiCard(BuildContext context, ImeiInfo info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('IMEI', style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _check15(context, '15 digits', info.lengthOk),
            _check15(context, 'Checksum valid', info.validChecksum),
            if (info.tac != null) ...[
              const SizedBox(height: 8),
              SpecRow('TAC', '${info.tac}  (identifies make & model)'),
              const SpecRow('Device', 'phone, tablet, watch or cellular modem'),
            ],
            if (!info.validChecksum)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'That doesn’t look like a valid IMEI. Dial *#06# on the phone, or '
                  'check Settings > About / the SIM tray.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (info.lengthOk) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _open('https://www.imei.info/?imei=${info.digits}'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Look up this IMEI'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _serialCard(BuildContext context, SerialInfo info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Serial number', style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SpecRow('Normalized', '${info.normalized}  (${info.normalized.length} chars)'),
            _check15(context, 'Apple-style serial', info.plausibleApple),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _open('https://checkcoverage.apple.com'),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Apple coverage'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _open('https://www.samsung.com/us/support/warranty/'),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Samsung warranty'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Other brands: search "<brand> warranty check".',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _check15(BuildContext context, String label, bool ok) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel,
              size: 18, color: ok ? const Color(0xFF2E7D32) : scheme.error),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
