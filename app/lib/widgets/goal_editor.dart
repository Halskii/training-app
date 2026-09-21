import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';

class GoalDraft {
  final String description;
  final String kind;
  final DateTime? targetDate;
  final List<String> events;

  const GoalDraft({
    required this.description,
    required this.kind,
    required this.targetDate,
    required this.events,
  });
}

/// Bottom sheet for adding a goal, or editing [existing]. Returns null if cancelled.
Future<GoalDraft?> showGoalEditor(BuildContext context, {GoalItem? existing}) {
  return showModalBottomSheet<GoalDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _GoalEditor(existing: existing),
  );
}

class _GoalEditor extends StatefulWidget {
  final GoalItem? existing;
  const _GoalEditor({this.existing});

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _events =
      TextEditingController(text: widget.existing?.events.join(', ') ?? '');
  late String _kind = widget.existing?.kind ?? 'long_term';
  late DateTime? _targetDate = widget.existing?.targetDate;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _events.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _targetDate ?? now.add(const Duration(days: 84));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.isBefore(now) ? initial : now,
      lastDate: DateTime(now.year + 6),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  void _save() {
    final description = _description.text.trim();
    if (description.isEmpty) {
      setState(() => _error = 'Describe your goal first');
      return;
    }
    Navigator.of(context).pop(GoalDraft(
      description: description,
      kind: _kind,
      targetDate: _targetDate,
      events: _kind == 'competition'
          ? _events.text
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(widget.existing == null ? 'Add goal' : 'Edit goal', style: t.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            minLines: 1,
            maxLines: 3,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Your goal',
              hintText: 'e.g. Squat 405 lb, or powerlifting meet in 12 weeks',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('kind-$_kind'),
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Goal type'),
            items: [
              for (final e in goalKindLabels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _kind = v!),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(_targetDate == null
                ? 'Target date (optional)'
                : formatDate(_targetDate!)),
            subtitle: _kind == 'competition' && _targetDate == null
                ? const Text('Your coach plans backward from the date')
                : null,
            trailing: _targetDate == null
                ? null
                : IconButton(
                    tooltip: 'Clear date',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _targetDate = null),
                  ),
            onTap: _pickDate,
          ),
          if (_kind == 'competition') ...[
            const SizedBox(height: 4),
            TextField(
              controller: _events,
              decoration: const InputDecoration(
                labelText: 'Events (optional)',
                helperText: 'Separate with commas, e.g. Log press, Yoke, Atlas stones',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(onPressed: _save, child: const Text('Save')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
