import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../format.dart';
import '../widgets/goal_editor.dart';

class GoalsScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onPlanCreated;

  const GoalsScreen({super.key, required this.state, required this.onPlanCreated});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _years = TextEditingController();
  final _injuries = TextEditingController();
  String _level = 'beginner';
  int _days = 4;
  bool _prefilled = false;

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _state.addListener(_prefill);
    // The profile may already be loaded by the time this screen is built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
  }

  @override
  void dispose() {
    _state.removeListener(_prefill);
    _years.dispose();
    _injuries.dispose();
    super.dispose();
  }

  // Fill the plan settings from the saved profile once, so returning users don't retype them.
  void _prefill() {
    final a = _state.athlete;
    if (_prefilled || a == null || !mounted) return;
    _prefilled = true;
    setState(() {
      _level = a.trainingLevel ?? _level;
      // Clamped in case the saved value predates the 5-day cap.
      _days = (a.trainingDaysPerWeek ?? _days).clamp(minTrainingDays, maxTrainingDays);
      final years = a.trainingAgeYears;
      if (years != null) {
        _years.text = years == years.roundToDouble() ? '${years.toInt()}' : '$years';
      }
      _injuries.text = a.reportedInjuries ?? '';
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _toast(e.toString());
    }
  }

  Future<void> _addGoal() async {
    final d = await showGoalEditor(context);
    if (d == null) return;
    await _run(() => _state.addGoal(
        description: d.description,
        kind: d.kind,
        targetDate: d.targetDate,
        events: d.events));
  }

  Future<void> _editGoal(GoalItem g) async {
    final d = await showGoalEditor(context, existing: g);
    if (d == null) return;
    await _run(() => _state.updateGoal(g.id,
        description: d.description,
        kind: d.kind,
        targetDate: d.targetDate,
        events: d.events));
  }

  Future<void> _removeGoal(GoalItem g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this goal?'),
        content: Text('"${g.description}"\n\n'
            'Your current program is not changed automatically.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _run(() => _state.deleteGoal(g.id));
  }

  Future<bool> _confirmReplace() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Replace your current program?'),
        content: const Text(
          'Creating a new plan replaces the program you are on now, including '
          'any edits you made and the workouts already built. Your goals stay.\n\n'
          'To change your current plan instead (a new injury, a swapped '
          'exercise), use "Adjust plan" on the Programs tab.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep my program')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Replace program')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _createPlan() async {
    if (_state.plan != null && !await _confirmReplace()) return;
    final created = await _state.generate(
      trainingLevel: _level,
      trainingAgeYears: double.tryParse(_years.text),
      trainingDaysPerWeek: _days,
      injuries: _injuries.text.trim(),
    );
    if (created && mounted) widget.onPlanCreated();
  }

  String _goalSubtitle(GoalItem g) {
    final parts = [
      goalKindLabels[g.kind] ?? g.kind,
      if (g.targetDate != null) formatDate(g.targetDate!),
      if (g.events.isNotEmpty) g.events.join(', '),
    ];
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final goals = _state.athlete?.goals ?? const <GoalItem>[];
        final t = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final hasPlan = _state.plan != null;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Your goals', style: t.titleMedium),
                const SizedBox(height: 8),
                if (goals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No goals yet. Add one so your coach knows what you are working toward.',
                      style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                for (final g in goals)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: Text(g.description),
                      subtitle: Text(_goalSubtitle(g)),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Goal options',
                        onSelected: (v) => v == 'edit' ? _editGoal(g) : _removeGoal(g),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Edit'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline),
                              title: Text('Remove'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _addGoal,
                    icon: const Icon(Icons.add),
                    label: const Text('Add goal'),
                  ),
                ),
                if (_state.goalsChangedSincePlan) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: scheme.secondaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Your goals changed'),
                      subtitle: const Text(
                          'Your current plan was built for your earlier goals. '
                          'Create a new plan below to reflect the change.'),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Text('Training plan', style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Your coach builds a 12-week plan around all of your goals.',
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('level-$_level'),
                        isExpanded: true,
                        initialValue: _level,
                        decoration: const InputDecoration(labelText: 'Training level'),
                        items: const [
                          DropdownMenuItem(value: 'beginner', child: Text('Beginner')),
                          DropdownMenuItem(
                              value: 'intermediate', child: Text('Intermediate')),
                          DropdownMenuItem(value: 'seasoned', child: Text('Seasoned')),
                        ],
                        onChanged: (v) => setState(() => _level = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _years,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Years training'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('days-$_days'),
                  isExpanded: true,
                  initialValue: _days,
                  decoration: const InputDecoration(labelText: 'Training days per week'),
                  items: [
                    for (var d = minTrainingDays; d <= maxTrainingDays; d++)
                      DropdownMenuItem(value: d, child: Text('$d days')),
                  ],
                  onChanged: (v) => setState(() => _days = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _injuries,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Current injuries or concerns (optional)',
                    hintText: 'e.g. Minor labrum tear, overhead pressing is limited',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _state.planning || goals.isEmpty ? null : _createPlan,
                  child: Text(_state.planning
                      ? 'Your coach is planning...'
                      : (hasPlan ? 'Create new plan' : 'Plan my 12 weeks')),
                ),
                if (goals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Add a goal first.', style: t.bodySmall),
                  ),
                if (_state.planning) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (_state.planError != null) ...[
                  const SizedBox(height: 16),
                  Text(_state.planError!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
