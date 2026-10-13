import 'package:flutter/material.dart';

import '../knowledge.dart';
import '../widgets.dart';

class DiagnoseScreen extends StatefulWidget {
  const DiagnoseScreen({super.key, required this.knowledge});
  final Knowledge knowledge;

  @override
  State<DiagnoseScreen> createState() => _DiagnoseScreenState();
}

class _DiagnoseScreenState extends State<DiagnoseScreen> {
  final _controller = TextEditingController();
  String? _device; // null = auto / all
  List<Symptom> _matches = [];
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _diagnose() {
    final text = _controller.text.trim();
    FocusScope.of(context).unfocus();
    setState(() {
      _searched = true;
      _device ??= text.isEmpty ? null : widget.knowledge.detectDevice(text);
      _matches = widget.knowledge.detectSymptoms(text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text("What's wrong?", style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Describe it in your own words, or pick a device and tap a symptom below.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _diagnose(),
          decoration: InputDecoration(
            hintText: 'e.g. my phone won’t charge and gets hot',
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _diagnose),
          ),
        ),
        const SizedBox(height: 16),
        _devicePicker(context),
        const SizedBox(height: 8),
        if (_searched && _matches.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Diagnosis', style: Theme.of(context).textTheme.titleLarge),
          if (_device != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('For: ${deviceLabels[_device] ?? _device}',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 12),
          ..._matches.map((s) => _symptomResult(context, s)),
        ] else if (_searched && _matches.isEmpty && _controller.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: const ListTile(
              leading: Icon(Icons.help_outline),
              title: Text("Couldn't match that"),
              subtitle: Text('Try different words, or tap one of the common problems below.'),
            ),
          ),
        ],
        const Divider(height: 32),
        Text('Common problems', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._symptomsForDevice().map((s) => Card(
              child: ListTile(
                title: Text(s.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showCausesSheet(context, s, _device),
              ),
            )),
      ],
    );
  }

  Widget _devicePicker(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ChoiceChip(
          label: const Text('Any device'),
          selected: _device == null,
          onSelected: (_) => setState(() => _device = null),
        ),
        ...deviceLabels.entries.map((e) => ChoiceChip(
              label: Text(e.value),
              selected: _device == e.key,
              onSelected: (_) => setState(() => _device = e.key),
            )),
      ],
    );
  }

  List<Symptom> _symptomsForDevice() =>
      widget.knowledge.symptoms.where((s) => s.appliesTo(_device)).toList();

  Widget _symptomResult(BuildContext context, Symptom s) {
    if (!s.appliesTo(_device)) return const SizedBox.shrink();
    final causes = s.causesFor(_device);
    final top = causes.take(2).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title, style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (var i = 0; i < top.length; i++) CauseTile(cause: top[i], index: i + 1),
            if (causes.length > top.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => showCausesSheet(context, s, _device),
                  child: Text('See all ${causes.length} causes'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
