import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';

/// Lets the athlete tell the coach what changed, previews the coach's revision of
/// the block, and saves it only if they approve. Returns true if changes were applied.
Future<bool?> showAdjustSheet(
  BuildContext context, {
  required AppState state,
  required Block block,
  required int blockNumber,
  required int completedWeeks,
  String? initialRequest,
  bool initialIsInjury = true,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _AdjustSheet(
      state: state,
      block: block,
      blockNumber: blockNumber,
      completedWeeks: completedWeeks,
      initialRequest: initialRequest,
      initialIsInjury: initialIsInjury,
    ),
  );
}

enum _Stage { input, working, review }

class _AdjustSheet extends StatefulWidget {
  final AppState state;
  final Block block;
  final int blockNumber;
  final int completedWeeks;
  final String? initialRequest;
  final bool initialIsInjury;

  const _AdjustSheet({
    required this.state,
    required this.block,
    required this.blockNumber,
    required this.completedWeeks,
    required this.initialRequest,
    required this.initialIsInjury,
  });

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  late final _request = TextEditingController(text: widget.initialRequest ?? '');
  _Stage _stage = _Stage.input;
  late bool _isInjury = widget.initialIsInjury;
  bool _applying = false;
  String? _error;
  AdjustProposal? _proposal;

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    setState(() {
      _stage = _Stage.working;
      _error = null;
    });
    try {
      final p = await widget.state.proposeAdjustment(
        widget.block.id,
        request: _request.text.trim(),
        isInjury: _isInjury,
        completedWeeks: widget.completedWeeks,
      );
      if (mounted) {
        setState(() {
          _proposal = p;
          _stage = _Stage.review;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _stage = _Stage.input;
        });
      }
    }
  }

  Future<void> _apply() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    final ok = await widget.state.saveBlockDetail(widget.block.id, _proposal!.detail);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _applying = false;
        _error = widget.state.blockError ?? 'Could not save the changes.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: switch (_stage) {
          _Stage.input => _inputChildren(context),
          _Stage.working => _workingChildren(context),
          _Stage.review => _reviewChildren(context),
        },
      ),
    );
  }

  List<Widget> _inputChildren(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return [
      Text('Adjust Block ${widget.blockNumber}', style: t.titleLarge),
      const SizedBox(height: 8),
      Text(
        'Tell your coach what changed. You will see the proposed changes and '
        'approve them before anything is saved.',
        style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      if (widget.completedWeeks > 0) ...[
        const SizedBox(height: 8),
        Text(
          widget.completedWeeks == 1
              ? 'Week 1 is already done and will not change.'
              : 'Weeks 1-${widget.completedWeeks} are already done and will not change.',
          style: t.bodySmall,
        ),
      ],
      const SizedBox(height: 16),
      TextField(
        controller: _request,
        minLines: 3,
        maxLines: 6,
        maxLength: 2000,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'What changed?',
          hintText: 'e.g. My left shoulder started hurting on overhead press, '
              'but bench and rows feel fine.',
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _isInjury,
        onChanged: (v) => setState(() => _isInjury = v),
        title: const Text('This is a new injury or pain'),
        subtitle: const Text(
            'Your coach will remember it when planning future blocks and phases.'),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: TextStyle(color: scheme.error)),
      ],
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _request.text.trim().isEmpty ? null : _ask,
              child: const Text('Ask coach'),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _workingChildren(BuildContext context) => [
        const SizedBox(height: 32),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Text('Your coach is reviewing your program',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('This usually takes about a minute.', textAlign: TextAlign.center),
        const SizedBox(height: 32),
      ];

  List<Widget> _reviewChildren(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final p = _proposal!;
    return [
      Text("Your coach's proposal", style: t.titleLarge),
      const SizedBox(height: 12),
      Card(
        color: scheme.secondaryContainer,
        margin: EdgeInsets.zero,
        child: Padding(padding: const EdgeInsets.all(16), child: Text(p.summary)),
      ),
      const SizedBox(height: 16),
      Text('What changes', style: t.titleMedium),
      const SizedBox(height: 4),
      for (final c in p.changes)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 8),
                child: Icon(Icons.swap_horiz, size: 18),
              ),
              Expanded(child: Text(c)),
            ],
          ),
        ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: scheme.error)),
      ],
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
                onPressed: _applying ? null : () => Navigator.of(context).pop(false),
                child: const Text('Discard')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _applying ? null : _apply,
              child: Text(_applying ? 'Applying...' : 'Apply changes'),
            ),
          ),
        ],
      ),
    ];
  }
}
