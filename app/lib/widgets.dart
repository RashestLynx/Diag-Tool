import 'package:flutter/material.dart';

import 'knowledge.dart';
import 'scan/report.dart';
import 'theme.dart';

/// A finding from the scan: coloured status chip, detail, and fix steps.
class FindingCard extends StatelessWidget {
  const FindingCard({super.key, required this.finding, this.symptom});

  final Finding finding;
  final Symptom? symptom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = levelStyle(finding.level, scheme);
    return Card(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(style.icon, color: style.color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(finding.title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (finding.detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 32),
                child: Text(finding.detail,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            if (finding.fixes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...finding.fixes.map((f) => _Bullet(f)),
            ],
            if (symptom != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton.icon(
                  onPressed: () => showCausesSheet(context, symptom!, null),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text('More on "${symptom!.title}"'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.arrow_right, size: 18),
          ),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// One cause with its likelihood badge, optional safety warning and fix steps.
class CauseTile extends StatelessWidget {
  const CauseTile({super.key, required this.cause, this.index});

  final Cause cause;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = likelihoodColor(cause.likelihood, scheme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (index != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('$index.',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
              Expanded(
                child: Text(cause.name,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(cause.likelihoodLabel,
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (cause.warning != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department, color: scheme.onErrorContainer, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(cause.warning!,
                        style: TextStyle(
                            color: scheme.onErrorContainer, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          ...cause.fixes.map((f) => _Bullet(f)),
        ],
      ),
    );
  }
}

/// Bottom sheet with every cause + fix for one symptom.
void showCausesSheet(BuildContext context, Symptom symptom, String? device) {
  final causes = symptom.causesFor(device);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(symptom.title, style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Likely causes, most likely first. Work down the list.',
              style: Theme.of(ctx).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          for (var i = 0; i < causes.length; i++) CauseTile(cause: causes[i], index: i + 1),
        ],
      ),
    ),
  );
}

/// A simple labelled row used on the device summary card.
class SpecRow extends StatelessWidget {
  const SpecRow(this.label, this.value, {super.key, this.icon});
  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
