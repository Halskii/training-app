import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../format.dart';
import '../widgets/adjust_sheet.dart';
import '../widgets/exercise_editor.dart';

const _wideBreakpoint = 760.0;

class ProgramsScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onSetGoal;
  final DateTime Function()? clock; // overridable so tests can pin "today"

  const ProgramsScreen({
    super.key,
    required this.state,
    required this.onSetGoal,
    this.clock,
  });

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  int _block = 0;
  int _day = 0;
  int _week = 0;
  String? _autoSelectedFor;

  AppState get _state => widget.state;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  Future<void> _adjust(Block block, int blockNumber, int completedWeeks) async {
    final applied = await showAdjustSheet(
      context,
      state: _state,
      block: block,
      blockNumber: blockNumber,
      completedWeeks: completedWeeks,
    );
    if (applied == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Program updated')));
    }
  }

  Future<void> _rebuild(Block block, int blockNumber, int completedWeeks) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: Text('Rebuild Block $blockNumber?'),
        content: Text(
          'Your coach will write this block from scratch. This replaces its '
          'current workouts, including any edits you made'
          '${completedWeeks > 0 ? ' and the weeks you have already completed' : ''}.\n\n'
          'To change just part of it, use "Adjust plan" instead.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Rebuild')),
        ],
      ),
    );
    if (ok != true) return;
    await _state.buildBlock(block.id, regenerate: true);
    if (_state.blockError != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not rebuild: ${_state.blockError}')),
      );
    }
  }

  Future<void> _planNext(Macrocycle plan) async {
    var level = _state.athlete?.trainingLevel ?? 'intermediate';
    var days = (_state.athlete?.trainingDaysPerWeek ?? 4).clamp(minTrainingDays, maxTrainingDays);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Plan Phase ${plan.phaseNumber + 1}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your coach will plan your next 12 weeks, building on what '
                  'you just did. Update your level or schedule if they changed.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: level,
                decoration: const InputDecoration(labelText: 'Training level'),
                items: const [
                  DropdownMenuItem(value: 'beginner', child: Text('Beginner')),
                  DropdownMenuItem(value: 'intermediate', child: Text('Intermediate')),
                  DropdownMenuItem(value: 'seasoned', child: Text('Seasoned')),
                ],
                onChanged: (v) => level = v!,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: days,
                decoration: const InputDecoration(labelText: 'Training days per week'),
                items: [
                  for (var d = minTrainingDays; d <= maxTrainingDays; d++)
                    DropdownMenuItem(value: d, child: Text('$d days')),
                ],
                onChanged: (v) => days = v!,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Plan next phase')),
        ],
      ),
    );
    if (go == true) {
      await _state.planNextPhase(trainingLevel: level, trainingDaysPerWeek: days);
    }
  }

  Future<void> _save(Block block, BlockDetail edited) async {
    final ok = await _state.saveBlockDetail(block.id, edited);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save your changes. ${_state.blockError ?? ''}')),
      );
    }
  }

  Future<void> _editExercise(Block block, int dayIdx, int exIdx) async {
    final copy = block.detail!.copy();
    final exercises = copy.days[dayIdx].exercises;
    final result =
        await showExerciseEditor(context, exercise: exercises[exIdx], isNew: false);
    if (result == null) return;
    if (result.deleted) {
      exercises.removeAt(exIdx);
    } else {
      exercises[exIdx] = result.exercise!;
    }
    await _save(block, copy);
  }

  Future<void> _addExercise(Block block, int dayIdx) async {
    final copy = block.detail!.copy();
    final blank = Exercise(
      name: '',
      weeks: List.generate(block.numWeeks, (_) => WeekRx()),
    );
    final result = await showExerciseEditor(context, exercise: blank, isNew: true);
    if (result?.exercise == null) return;
    copy.days[dayIdx].exercises.add(result!.exercise!);
    await _save(block, copy);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        if (_state.loading && _state.plan == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final plan = _state.plan;
        return RefreshIndicator(
          onRefresh: _state.load,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _wideBreakpoint;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_state.loadError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(_state.loadError!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        ),
                      if (plan == null)
                        _EmptyState(onSetGoal: widget.onSetGoal)
                      else
                        ..._planChildren(context, plan, wide),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _planChildren(BuildContext context, Macrocycle plan, bool wide) {
    final t = Theme.of(context).textTheme;

    // Where the athlete is in the phase, and (once per plan) open on that block and week.
    final rawWeek = plan.currentWeek(_now());
    final complete = rawWeek > plan.totalWeeks;
    final week = rawWeek.clamp(1, plan.totalWeeks);
    final currentBlockIdx =
        plan.blocks.indexWhere((b) => week >= b.weekStart && week <= b.weekEnd);
    if (_autoSelectedFor != plan.id) {
      _autoSelectedFor = plan.id;
      _block = currentBlockIdx < 0 ? 0 : currentBlockIdx;
      final b = plan.blocks[_block];
      _week = (week - b.weekStart).clamp(0, b.numWeeks - 1);
      _day = 0;
    }

    final blockIdx = _block.clamp(0, plan.blocks.length - 1);
    final block = plan.blocks[blockIdx];
    final detail = block.detail;
    final completedWeeks = (rawWeek - block.weekStart).clamp(0, block.numWeeks);
    final currentWeekIdx = complete || blockIdx != currentBlockIdx ? null : week - block.weekStart;

    return [
      _PhaseBanner(
        plan: plan,
        week: rawWeek,
        complete: complete,
        planning: _state.planning,
        error: _state.planError,
        onPlanNext: () => _planNext(plan),
      ),
      if (plan.coachNote.isNotEmpty)
        _NoteTile(title: "Coach's note", text: plan.coachNote, highlight: true),
      const SizedBox(height: 4),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (var i = 0; i < plan.blocks.length; i++)
              ButtonSegment(
                value: i,
                label: Text(i == currentBlockIdx && !complete
                    ? 'Block ${i + 1} •'
                    : 'Block ${i + 1}'),
              ),
          ],
          selected: {blockIdx},
          onSelectionChanged: (s) => setState(() {
            _block = s.first;
            _day = 0;
            _week = 0;
          }),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '${block.phase.toUpperCase()}  ·  Weeks ${block.weekStart}-${block.weekEnd}',
        style: t.titleMedium,
      ),
      const SizedBox(height: 4),
      _OverviewTile(block: block),
      const SizedBox(height: 8),
      if (_state.isBuilding(block.id))
        _BuildingCard(blockNumber: blockIdx + 1)
      else if (detail == null)
        _BuildPrompt(
          blockNumber: blockIdx + 1,
          canBuild: blockIdx == 0 || plan.blocks[blockIdx - 1].detail != null,
          error: _state.blockError,
          onBuild: () => _state.buildBlock(block.id),
        )
      else
        ..._detailChildren(
            context, block, blockIdx + 1, detail, wide, completedWeeks, currentWeekIdx),
    ];
  }

  List<Widget> _detailChildren(
    BuildContext context,
    Block block,
    int blockNumber,
    BlockDetail detail,
    bool wide,
    int completedWeeks,
    int? currentWeekIdx,
  ) {
    final t = Theme.of(context).textTheme;
    final dayIdx = _day.clamp(0, detail.days.length - 1);
    final weekIdx = _week.clamp(0, block.numWeeks - 1);
    final day = detail.days[dayIdx];
    final labels = _exerciseLabels(day.exercises);
    final finished = completedWeeks >= block.numWeeks;

    return [
      if (detail.coachNote.isNotEmpty)
        _NoteTile(title: 'About this block', text: detail.coachNote),
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tooltip(
              message: finished ? 'This block is finished' : '',
              child: OutlinedButton.icon(
                onPressed:
                    finished ? null : () => _adjust(block, blockNumber, completedWeeks),
                icon: const Icon(Icons.healing_outlined),
                label: const Text('Adjust plan'),
              ),
            ),
            TextButton.icon(
              onPressed: () => _rebuild(block, blockNumber, completedWeeks),
              icon: const Icon(Icons.refresh),
              label: const Text('Rebuild block'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (var i = 0; i < detail.days.length; i++)
            ChoiceChip(
              label: Text('Day ${i + 1}'),
              selected: i == dayIdx,
              onSelected: (_) => setState(() => _day = i),
            ),
        ],
      ),
      if (!wide) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (var i = 0; i < block.numWeeks; i++)
                ButtonSegment(
                  value: i,
                  label: Text(i == currentWeekIdx ? 'Wk ${i + 1} •' : 'Wk ${i + 1}'),
                ),
            ],
            selected: {weekIdx},
            onSelectionChanged: (s) => setState(() => _week = s.first),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(day.title, style: t.titleLarge),
      const SizedBox(height: 8),
      if (day.warmup.isNotEmpty) _WarmupTile(sections: day.warmup),
      const SizedBox(height: 4),
      for (var i = 0; i < day.exercises.length; i++)
        _ExerciseCard(
          label: labels[i],
          exercise: day.exercises[i],
          week: weekIdx,
          wide: wide,
          onTap: () => _editExercise(block, dayIdx, i),
        ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => _addExercise(block, dayIdx),
          icon: const Icon(Icons.add),
          label: const Text('Add exercise'),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  /// Standalone exercises are numbered 1, 2, 3...; supersets are A1/A2, B1/B2...
  static List<String> _exerciseLabels(List<Exercise> exercises) {
    final labels = <String>[];
    final perGroup = <String, int>{};
    var n = 0;
    for (final e in exercises) {
      final g = e.group;
      if (g == null || g.isEmpty) {
        labels.add('${++n}');
      } else {
        final k = (perGroup[g] ?? 0) + 1;
        perGroup[g] = k;
        labels.add('$g$k');
      }
    }
    return labels;
  }
}

class _PhaseBanner extends StatelessWidget {
  final Macrocycle plan;
  final int week;
  final bool complete;
  final bool planning;
  final String? error;
  final VoidCallback onPlanNext;

  const _PhaseBanner({
    required this.plan,
    required this.week,
    required this.complete,
    required this.planning,
    required this.error,
    required this.onPlanNext,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (!complete) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('Phase ${plan.phaseNumber}  ·  Week $week of ${plan.totalWeeks}',
            style: t.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
      );
    }

    return Card(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events_outlined, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Phase ${plan.phaseNumber} complete',
                      style: t.titleMedium?.copyWith(color: scheme.onPrimaryContainer)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Nice work finishing all ${plan.totalWeeks} weeks. Your coach can plan '
              'your next phase, building on what you just did and your current goals.',
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: planning ? null : onPlanNext,
              child: Text(planning ? 'Your coach is planning...' : 'Plan next phase'),
            ),
            if (planning) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onSetGoal;
  const _EmptyState({required this.onSetGoal});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.fitness_center, size: 64),
        const SizedBox(height: 16),
        Text('No program yet', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Set a goal and your coach will build a 12-week plan around it.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onSetGoal, child: const Text('Set a goal')),
      ],
    );
  }
}

class _NoteTile extends StatelessWidget {
  final String title;
  final String text;
  final bool highlight;
  const _NoteTile({required this.title, required this.text, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: highlight ? scheme.secondaryContainer : null,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.sports_outlined),
        title: Text(title),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(text)],
      ),
    );
  }
}

class _OverviewTile extends StatelessWidget {
  final Block block;
  const _OverviewTile({required this.block});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text('Block overview'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Volume: ${block.volumeTrend}'),
          Text('Intensity: ${block.intensityTrend}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [for (final m in block.movementFocus) Chip(label: Text(m))],
          ),
          const SizedBox(height: 8),
          Text(block.rationale),
        ],
      ),
    );
  }
}

class _BuildingCard extends StatelessWidget {
  final int blockNumber;
  const _BuildingCard({required this.blockNumber});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Your coach is writing your Block $blockNumber workouts',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            const Text('This usually takes about a minute.', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _BuildPrompt extends StatelessWidget {
  final int blockNumber;
  final bool canBuild;
  final String? error;
  final VoidCallback onBuild;

  const _BuildPrompt({
    required this.blockNumber,
    required this.canBuild,
    required this.error,
    required this.onBuild,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.edit_note, size: 48),
            const SizedBox(height: 12),
            Text("Block $blockNumber workouts aren't built yet",
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Your coach writes each block right before you need it, so it can '
              'build on the one before.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (canBuild)
              FilledButton(onPressed: onBuild, child: Text('Build Block $blockNumber workouts'))
            else
              Text('Build Block ${blockNumber - 1} first.',
                  style: Theme.of(context).textTheme.labelLarge),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _WarmupTile extends StatelessWidget {
  final List<WarmupSection> sections;
  const _WarmupTile({required this.sections});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.local_fire_department_outlined),
        title: const Text('Warm-up'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in sections) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                s.prescription == null ? s.title : '${s.title}  ·  ${s.prescription}',
                style: t.titleSmall,
              ),
            ),
            for (final item in s.items)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('•  $item'),
              ),
            if (s.notes != null && s.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(s.notes!, style: t.bodySmall?.copyWith(color: muted)),
              ),
          ],
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final String label;
  final Exercise exercise;
  final int week;
  final bool wide;
  final VoidCallback onTap;

  const _ExerciseCard({
    required this.label,
    required this.exercise,
    required this.week,
    required this.wide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final cue = exercise.cue;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(label,
                        style: t.labelLarge?.copyWith(color: scheme.onPrimaryContainer)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exercise.name, style: t.titleMedium),
                        if (cue != null && cue.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(cue,
                                style: t.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.edit_outlined, size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < exercise.weeks.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              right: i == exercise.weeks.length - 1 ? 0 : 8),
                          child: _WeekCell(
                              label: 'Wk ${i + 1}', rx: exercise.weeks[i], compact: true),
                        ),
                      ),
                  ],
                )
              else if (week < exercise.weeks.length)
                _WeekCell(label: 'Wk ${week + 1}', rx: exercise.weeks[week]),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekCell extends StatelessWidget {
  final String label;
  final WeekRx rx;
  final bool compact;

  const _WeekCell({required this.label, required this.rx, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final scheme_ = rx.scheme;
    final effort = (rx.effort ?? '').trim();
    final note = (rx.note ?? '').trim();
    final empty = scheme_.isEmpty && effort.isEmpty && note.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          if (empty)
            Text('—', style: t.titleMedium?.copyWith(color: scheme.onSurfaceVariant))
          else ...[
            if (scheme_.isNotEmpty)
              Text(scheme_, style: compact ? t.titleSmall : t.titleLarge),
            if (effort.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(effort,
                    style: (compact ? t.bodySmall : t.bodyMedium)
                        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
              ),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(note,
                    style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ),
          ],
        ],
      ),
    );
  }
}
