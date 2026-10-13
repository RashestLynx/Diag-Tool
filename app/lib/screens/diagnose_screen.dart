import 'package:flutter/material.dart';

import '../knowledge.dart';
import '../reference/reference.dart';
import '../widgets.dart';

class DiagnoseScreen extends StatefulWidget {
  const DiagnoseScreen({super.key, required this.knowledge, required this.reference});
  final Knowledge knowledge;
  final Reference reference;

  @override
  State<DiagnoseScreen> createState() => _DiagnoseScreenState();
}

class _DiagnoseScreenState extends State<DiagnoseScreen> {
  final _controller = TextEditingController();
  final _dtcController = TextEditingController();
  String? _device; // null = auto / all
  List<Symptom> _matches = [];
  bool _searched = false;
  DtcCode? _dtc;
  bool _dtcSearched = false;

  @override
  void dispose() {
    _controller.dispose();
    _dtcController.dispose();
    super.dispose();
  }

  void _lookupDtc() {
    FocusScope.of(context).unfocus();
    setState(() {
      _dtcSearched = true;
      _dtc = widget.reference.dtc(_dtcController.text);
    });
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
        const Divider(height: 32),
        _carCodeCard(context),
      ],
    );
  }

  Widget _dtcFallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final raw = _dtcController.text.trim().toUpperCase();
    if (raw.isEmpty) {
      return Text('Enter a code above.', style: TextStyle(color: scheme.onSurfaceVariant));
    }
    final decoded = widget.reference.describeDtc(raw);
    if (decoded == null) {
      return Text('"$raw" isn’t a standard OBD-II code (they look like P0420, '
          'C1234, B0010, U0100).', style: TextStyle(color: scheme.onSurfaceVariant));
    }
    // Valid code we don't have a detailed entry for: explain its structure.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(raw, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(decoded, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          raw[1] == '1'
              ? 'This is a manufacturer-specific code, so its exact meaning differs by '
                  'brand. Search "$raw <your make/model>" for the definition.'
              : 'We don’t have a detailed fix for this exact code yet. Search '
                  '"$raw" for your make/model; a shop scan tool with live data is authoritative.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _carCodeCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Car trouble code (OBD-II)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Got a check-engine code from a scanner? Enter it (e.g. P0420) for what '
            'it means and how to fix it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _dtcController,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _lookupDtc(),
                decoration: InputDecoration(
                  labelText: 'Code (e.g. P0420)',
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(onPressed: _lookupDtc, child: const Text('Look up')),
          ],
        ),
        if (_dtcSearched) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _dtc == null
                  ? _dtcFallback(context)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(_dtc!.code, style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(_dtc!.system,
                                style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text(_dtc!.meaning, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('Fix: ${_dtc!.fix}'),
                      ],
                    ),
            ),
          ),
        ],
        const SizedBox(height: 8),
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
