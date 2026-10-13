import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../knowledge.dart';
import '../scan/report.dart';
import '../scan/scanner.dart';
import '../widgets.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.knowledge});
  final Knowledge knowledge;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  DeviceReport? _report;
  List<Finding>? _findings;
  bool _scanning = false;
  Object? _error;

  bool get _supported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final report = await scanDevice();
      final findings = analyze(report);
      if (mounted) setState(() => (_report = report, _findings = findings));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return _Placeholder(
        icon: Icons.devices_other,
        title: 'Scan runs on a real device',
        body: 'Open this app on the phone, tablet or computer you want to check. '
            'You can still use Diagnose and Identify here.',
      );
    }
    if (_error != null) {
      return _Placeholder(
        icon: Icons.error_outline,
        title: "Couldn't finish the scan",
        body: '$_error',
        action: FilledButton(onPressed: _scan, child: const Text('Try again')),
      );
    }
    if (_report == null) {
      return _Placeholder(
        icon: Icons.health_and_safety_outlined,
        title: 'Check this device',
        body: 'Look at storage, memory, battery, temperature and more, with fixes '
            'for anything that needs attention.',
        action: FilledButton.icon(
          onPressed: _scanning ? null : _scan,
          icon: _scanning
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow),
          label: Text(_scanning ? 'Scanning…' : 'Run scan'),
        ),
      );
    }
    return _results(context);
  }

  Widget _results(BuildContext context) {
    final report = _report!;
    final findings = _findings!;
    final problems = findings.where((f) => f.level != Level.ok).toList();
    final allClear = problems.every((f) => f.level == Level.info);

    return RefreshIndicator(
      onRefresh: _scan,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _deviceCard(context, report),
          const SizedBox(height: 16),
          if (allClear)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Nothing wrong found'),
                subtitle: const Text('If something still feels off, try the Diagnose tab.'),
              ),
            ),
          ...findings.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FindingCard(
                    finding: f, symptom: f.symptomKey == null ? null : widget.knowledge.symptom(f.symptomKey!)),
              )),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan again'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceCard(BuildContext context, DeviceReport r) {
    final scheme = Theme.of(context).colorScheme;
    final kindLabel = deviceLabels[r.kind] ?? r.kind;
    final icon = switch (r.kind) {
      'phone' => Icons.smartphone,
      'tablet' => Icons.tablet,
      'laptop' => Icons.laptop,
      _ => Icons.desktop_windows,
    };
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 30, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    r.kindDetail == null ? kindLabel : '$kindLabel · ${r.kindDetail}',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold, color: scheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (r.makeModel != null && r.makeModel!.isNotEmpty)
              SpecRow('Make / model', r.makeModel!, icon: Icons.memory),
            if (r.os.isNotEmpty) SpecRow('System', r.os, icon: Icons.settings),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}
