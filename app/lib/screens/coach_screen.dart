import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../app_state.dart';
import '../widgets/adjust_sheet.dart';

const _suggestions = [
  'Why is my program set up this way?',
  'Something feels off today',
  'How hard should an RPE 7 feel?',
];

class CoachScreen extends StatefulWidget {
  final AppState state;
  final DateTime Function()? clock; // overridable so tests can pin "today"

  const CoachScreen({super.key, required this.state, this.clock});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _shownCount = 0;
  bool _wasSending = false;

  AppState get _state => widget.state;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _state.addListener(_keepNewestInView);
  }

  @override
  void dispose() {
    _state.removeListener(_keepNewestInView);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _keepNewestInView() {
    if (_state.chat.length == _shownCount && _state.chatSending == _wasSending) return;
    _shownCount = _state.chat.length;
    _wasSending = _state.chatSending;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _state.chatSending) return;
    _input.clear();
    final ok = await _state.sendChat(text);
    if (!ok && mounted) {
      // Put the message back so nothing typed is lost.
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
    } else if (mounted && _input.text.trim().isEmpty) {
      // Enter can leave a stray newline behind on some platforms.
      _input.clear();
    }
  }

  Future<void> _review(ChatAction action) async {
    final plan = _state.plan;
    final index = plan?.blocks.indexWhere((b) => b.id == action.blockId) ?? -1;
    if (plan == null || index < 0) {
      _toast('That block is no longer part of your current plan.');
      return;
    }
    final block = plan.blocks[index];
    if (block.detail == null) {
      _toast('Block ${index + 1} has no workouts to change yet.');
      return;
    }
    final completed = plan.completedWeeks(block, _now());
    if (completed >= block.numWeeks) {
      _toast('Block ${index + 1} is already finished.');
      return;
    }
    final applied = await showAdjustSheet(
      context,
      state: _state,
      block: block,
      blockNumber: index + 1,
      completedWeeks: completed,
      initialRequest: action.request,
      initialIsInjury: action.isInjury,
    );
    if (applied == true) _toast('Program updated');
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text(
          'Your coach will no longer see this chat. Notes it saved about you '
          '(like how sessions felt) are kept and still shape your plans.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear chat')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _state.clearChat();
    } catch (e) {
      _toast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final messages = _state.chat;
        final scheme = Theme.of(context).colorScheme;
        final canSend = _input.text.trim().isNotEmpty && !_state.chatSending;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                if (messages.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _state.chatSending ? null : _confirmClear,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: const Text('Clear chat'),
                    ),
                  ),
                Expanded(
                  child: messages.isEmpty && !_state.chatSending
                      ? _EmptyState(onSuggestion: _send)
                      : ListView(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          children: [
                            for (final m in messages) _Bubble(message: m, onReview: _review),
                            if (_state.chatSending) const _TypingBubble(),
                          ],
                        ),
                ),
                if (_state.chatError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 18, color: scheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_state.chatError!,
                              style: TextStyle(color: scheme.error)),
                        ),
                        IconButton(
                          tooltip: 'Dismiss',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _state.dismissChatError,
                        ),
                      ],
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: CallbackShortcuts(
                            bindings: {
                              const SingleActivator(LogicalKeyboardKey.enter): () => _send(),
                            },
                            child: TextField(
                              controller: _input,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 2000,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: 'Message your coach',
                                counterText: '',
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Send',
                          onPressed: canSend ? () => _send() : null,
                          icon: const Icon(Icons.arrow_upward),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final void Function(String) onSuggestion;
  const _EmptyState({required this.onSuggestion});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 56),
            const SizedBox(height: 16),
            Text('Ask your coach anything', style: t.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Questions about your program, how a session felt, or something '
              'that hurts. If your plan should change, your coach will offer it '
              'for you to review.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _suggestions)
                  ActionChip(label: Text(s), onPressed: () => onSuggestion(s)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final void Function(ChatAction) onReview;
  const _Bubble({required this.message, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final coach = message.fromCoach;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: coach ? Alignment.centerLeft : Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: coach ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: coach ? scheme.surfaceContainerHigh : scheme.primaryContainer,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(coach ? 4 : 16),
                    bottomRight: Radius.circular(coach ? 16 : 4),
                  ),
                ),
                child: SelectableText(
                  message.content,
                  style: t.bodyMedium?.copyWith(
                    color: coach ? scheme.onSurface : scheme.onPrimaryContainer,
                  ),
                ),
              ),
              if (coach)
                for (final a in message.actions) _ActionView(action: a, onReview: onReview),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionView extends StatelessWidget {
  final ChatAction action;
  final void Function(ChatAction) onReview;
  const _ActionView({required this.action, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    if (action.type == ChatAction.adjustSuggestion) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton.icon(
          onPressed: () => onReview(action),
          icon: const Icon(Icons.healing_outlined),
          label: Text('Review change to Block ${action.blockNumber}'),
        ),
      );
    }
    if (action.type == ChatAction.feedbackSaved) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bookmark_added_outlined, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Noted: ${action.content}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text('Your coach is typing...',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
