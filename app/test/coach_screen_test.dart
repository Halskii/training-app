import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:training_app/screens/coach_screen.dart';

import 'test_helpers.dart';

// The fixture plan starts Mon 2026-09-14: 2026-09-30 is week 3 (block 1, weeks 1-4).
final _week3 = DateTime(2026, 9, 30);
const _block1 = '00000000-0000-0000-0000-000000000001';
const _block2 = '00000000-0000-0000-0000-000000000002';

Future<TestState> _pump(
  WidgetTester tester, {
  TestState? state,
  Size size = const Size(390, 844),
  DateTime? now,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final s = state ?? TestState();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(colorSchemeSeed: const Color(0xFF1F3A5F), brightness: Brightness.dark),
    home: Scaffold(body: CoachScreen(state: s, clock: () => now ?? _week3)),
  ));
  await tester.pumpAndSettle();
  return s;
}

Finder get _chatInput => find.widgetWithText(TextField, 'Message your coach');
Finder get _sendButton => find.byTooltip('Send');

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

void main() {
  testWidgets('empty state offers starter questions that send when tapped', (tester) async {
    final state = await _pump(tester);
    expect(find.text('Ask your coach anything'), findsOneWidget);
    expect(find.text('Clear chat'), findsNothing);

    await tester.tap(find.text('Something feels off today'));
    await tester.pumpAndSettle();
    expect(state.sentChats, ['Something feels off today']);
    expect(find.text('Something feels off today'), findsOneWidget); // now the athlete's bubble
    expect(find.text('Sounds good.'), findsOneWidget);
    expect(find.text('Ask your coach anything'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing and sending shows the message, a typing indicator, then the reply', (tester) async {
    final state = TestState()..holdChat = Completer<void>();
    await _pump(tester, state: state);

    await _type(tester, '  How is my week 3?  ');
    await tester.tap(_sendButton);
    await tester.pump();

    expect(state.sentChats, ['How is my week 3?']); // trimmed
    expect(find.text('How is my week 3?'), findsOneWidget);
    expect(find.text('Your coach is typing...'), findsOneWidget);
    expect(tester.widget<TextField>(_chatInput).controller!.text, isEmpty); // cleared on send
    // Can't send a second message while one is pending.
    await _type(tester, 'another');
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_upward)).onPressed, isNull);

    state.holdChat!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Your coach is typing...'), findsNothing);
    expect(find.text('Sounds good.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('send is disabled for empty or whitespace-only input', (tester) async {
    await _pump(tester);
    IconButton button() =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_upward));
    expect(button().onPressed, isNull);
    await _type(tester, '    ');
    expect(button().onPressed, isNull);
    await _type(tester, 'hi');
    expect(button().onPressed, isNotNull);
  });

  testWidgets('a failed send puts the text back and shows the error', (tester) async {
    final state = TestState()..failChat = true;
    await _pump(tester, state: state);

    await _type(tester, 'My knee hurts');
    await tester.tap(_sendButton);
    await tester.pumpAndSettle();

    expect(find.text('Could not reach your coach'), findsOneWidget);
    expect(tester.widget<TextField>(_chatInput).controller!.text, 'My knee hurts');
    expect(state.chat, isEmpty); // the unsent message isn't left dangling as if delivered

    // Retrying works and clears the error.
    state.failChat = false;
    await tester.tap(_sendButton);
    await tester.pumpAndSettle();
    expect(find.text('Could not reach your coach'), findsNothing);
    expect(find.text('Sounds good.'), findsOneWidget);
  });

  testWidgets('the error can be dismissed', (tester) async {
    final state = TestState()..chatError = 'Chat is not available yet';
    await _pump(tester, state: state);
    expect(find.text('Chat is not available yet'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Chat is not available yet'), findsNothing);
  });

  group('coach actions', () {
    Map<String, dynamic> adjust({String blockId = _block1, int number = 1}) => {
          'type': 'adjust_suggestion',
          'block_id': blockId,
          'block_number': number,
          'request': 'Left shoulder hurts on overhead press; avoid it.',
          'is_injury': true,
        };
    const note = {
      'type': 'feedback_saved',
      'kind': 'injury',
      'content': 'Left shoulder hurts on overhead press.',
    };

    TestState withReply(List<Map<String, dynamic>> actions) => TestState()
      ..chat = [
        chatMessage('user', 'my shoulder hurts', id: 'u1'),
        chatMessage('coach', 'I would swap the press.', actions: actions, id: 'c1'),
      ];

    testWidgets('shows what was noted and a button to review the change', (tester) async {
      await _pump(tester, state: withReply([adjust(), note]));
      expect(find.text('I would swap the press.'), findsOneWidget);
      expect(find.text('Noted: Left shoulder hurts on overhead press.'), findsOneWidget);
      expect(find.text('Review change to Block 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the review button opens the adjust sheet prefilled, and applying saves', (tester) async {
      final state = withReply([adjust()]);
      await _pump(tester, state: state);

      await tester.tap(find.text('Review change to Block 1'));
      await tester.pumpAndSettle();
      expect(find.text('Adjust Block 1'), findsOneWidget);
      expect(find.text('Weeks 1-2 are already done and will not change.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Left shoulder hurts on overhead press; avoid it.'),
          findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue); // flagged as an injury

      await tester.tap(find.text('Ask coach'));
      await tester.pumpAndSettle();
      expect(state.adjustRequests,
          ['Left shoulder hurts on overhead press; avoid it.|injury=true|done=2']);
      expect(state.saved, isEmpty); // nothing saved until approved

      await tester.tap(find.text('Apply changes'));
      await tester.pumpAndSettle();
      expect(state.saved.length, 1);
      expect(find.text('Program updated'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a non-injury suggestion opens with the injury switch off', (tester) async {
      final a = adjust()..['is_injury'] = false;
      await _pump(tester, state: withReply([a]));
      await tester.tap(find.text('Review change to Block 1'));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('explains when the block is no longer in the plan', (tester) async {
      // e.g. the plan was replaced after the suggestion was made.
      await _pump(tester, state: withReply([adjust(blockId: 'old-block')]));
      await tester.tap(find.text('Review change to Block 1'));
      await tester.pump();
      expect(find.text('That block is no longer part of your current plan.'), findsOneWidget);
    });

    testWidgets('explains when the block has no workouts yet', (tester) async {
      await _pump(tester, state: withReply([adjust(blockId: _block2, number: 2)]));
      await tester.tap(find.text('Review change to Block 2'));
      await tester.pump();
      expect(find.text('Block 2 has no workouts to change yet.'), findsOneWidget);
    });

    testWidgets('explains when the block is already finished', (tester) async {
      await _pump(tester, state: withReply([adjust()]), now: DateTime(2026, 11, 1));
      await tester.tap(find.text('Review change to Block 1'));
      await tester.pump();
      expect(find.text('Block 1 is already finished.'), findsOneWidget);
    });
  });

  group('clear chat', () {
    TestState withHistory() => TestState()
      ..chat = [
        chatMessage('user', 'hello', id: 'u1'),
        chatMessage('coach', 'hi there', id: 'c1'),
      ];

    testWidgets('asks first, and cancelling keeps the conversation', (tester) async {
      final state = withHistory();
      await _pump(tester, state: state);
      await tester.tap(find.text('Clear chat'));
      await tester.pumpAndSettle();
      expect(find.text('Clear this conversation?'), findsOneWidget);
      expect(find.textContaining('Notes it saved about you'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.clearCalls, 0);
      expect(find.text('hi there'), findsOneWidget);
    });

    testWidgets('confirming clears it and returns to the starter screen', (tester) async {
      final state = withHistory();
      await _pump(tester, state: state);
      await tester.tap(find.text('Clear chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear chat'));
      await tester.pumpAndSettle();
      expect(state.clearCalls, 1);
      expect(find.text('Ask your coach anything'), findsOneWidget);
    });
  });

  testWidgets('long conversations and long replies fit a small phone', (tester) async {
    final long = 'This is a long coaching reply. ' * 30;
    final state = TestState()
      ..chat = [
        for (var i = 0; i < 12; i++) ...[
          chatMessage('user', 'Question number $i about my program and how it feels', id: 'u$i'),
          chatMessage('coach', long, id: 'c$i', actions: [
            {'type': 'feedback_saved', 'kind': 'note', 'content': 'Note ' * 60},
            {
              'type': 'adjust_suggestion',
              'block_id': _block1,
              'block_number': 1,
              'request': 'x',
              'is_injury': false,
            },
          ]),
        ],
      ];
    await _pump(tester, state: state, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
    // Opens scrolled to the latest message... at least the input is usable.
    await _type(tester, 'still works');
    expect(tester.widget<TextField>(_chatInput).controller!.text, 'still works');
  });
}
