import 'package:flutter/material.dart';

import '../api.dart';

class ExerciseEditResult {
  final Exercise? exercise;
  final bool deleted;
  const ExerciseEditResult.saved(Exercise this.exercise) : deleted = false;
  const ExerciseEditResult.deleted()
      : exercise = null,
        deleted = true;
}

Future<ExerciseEditResult?> showExerciseEditor(
  BuildContext context, {
  required Exercise exercise,
  required bool isNew,
}) {
  return showModalBottomSheet<ExerciseEditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _ExerciseEditor(exercise: exercise, isNew: isNew),
  );
}

class _WeekControllers {
  final sets = TextEditingController();
  final reps = TextEditingController();
  final effort = TextEditingController();
  final note = TextEditingController();

  _WeekControllers(WeekRx rx) {
    sets.text = rx.sets?.toString() ?? '';
    reps.text = rx.reps ?? '';
    effort.text = rx.effort ?? '';
    note.text = rx.note ?? '';
  }

  void copyFrom(_WeekControllers o) {
    sets.text = o.sets.text;
    reps.text = o.reps.text;
    effort.text = o.effort.text;
    note.text = o.note.text;
  }

  WeekRx toWeekRx() {
    String? clean(String s) => s.trim().isEmpty ? null : s.trim();
    return WeekRx(
      sets: int.tryParse(sets.text.trim()),
      reps: clean(reps.text),
      effort: clean(effort.text),
      note: clean(note.text),
    );
  }

  void dispose() {
    sets.dispose();
    reps.dispose();
    effort.dispose();
    note.dispose();
  }
}

class _ExerciseEditor extends StatefulWidget {
  final Exercise exercise;
  final bool isNew;
  const _ExerciseEditor({required this.exercise, required this.isNew});

  @override
  State<_ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends State<_ExerciseEditor> {
  late final _name = TextEditingController(text: widget.exercise.name);
  late final _cue = TextEditingController(text: widget.exercise.cue ?? '');
  late final _group = TextEditingController(text: widget.exercise.group ?? '');
  late final List<_WeekControllers> _weeks =
      widget.exercise.weeks.map(_WeekControllers.new).toList();
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    _cue.dispose();
    _group.dispose();
    for (final w in _weeks) {
      w.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Give the exercise a name');
      return;
    }
    String? clean(String s) => s.trim().isEmpty ? null : s.trim();
    Navigator.of(context).pop(ExerciseEditResult.saved(Exercise(
      name: _name.text.trim(),
      group: clean(_group.text.toUpperCase()),
      cue: clean(_cue.text),
      weeks: _weeks.map((w) => w.toWeekRx()).toList(),
    )));
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete exercise?'),
        content: Text('Remove "${widget.exercise.name}" from this day.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(const ExerciseEditResult.deleted());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(widget.isNew ? 'Add exercise' : 'Edit exercise', style: t.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Exercise',
              errorText: _nameError,
            ),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cue,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes / cues'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _group,
            maxLength: 2,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Superset group (optional)',
              helperText: 'Give paired exercises the same letter, e.g. A',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Prescription by week', style: t.titleMedium)),
              if (_weeks.length > 1)
                TextButton(
                  onPressed: () => setState(() {
                    for (final w in _weeks.skip(1)) {
                      w.copyFrom(_weeks.first);
                    }
                  }),
                  child: const Text('Copy week 1 to all'),
                ),
            ],
          ),
          for (var i = 0; i < _weeks.length; i++) _WeekEditor(index: i, c: _weeks[i]),
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
          if (!widget.isNew)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: _confirmDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete exercise'),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekEditor extends StatelessWidget {
  final int index;
  final _WeekControllers c;
  const _WeekEditor({required this.index, required this.c});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Week ${index + 1}', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: c.sets,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Sets', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: c.reps,
                    decoration: const InputDecoration(labelText: 'Reps', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: c.effort,
                    decoration: const InputDecoration(
                        labelText: 'Effort', hintText: 'RPE 8', isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: c.note,
              decoration: const InputDecoration(labelText: 'Note', isDense: true),
            ),
          ],
        ),
      ),
    );
  }
}
