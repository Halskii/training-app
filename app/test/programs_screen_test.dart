import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:training_app/api.dart';
import 'package:training_app/screens/programs_screen.dart';

import 'test_helpers.dart';

// The fixture plan starts Mon 2026-09-14, so this is week 1 of 12.
final _week1 = DateTime(2026, 9, 20);
DateTime _weekN(int n) => DateTime(2026, 9, 14).add(Duration(days: 7 * (n - 1) + 2));

Future<TestState> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 2200),
  DateTime? now,
  TestState? state,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final s = state ?? TestState();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(colorSchemeSeed: const Color(0xFF1F3A5F), brightness: Brightness.dark),
    home: Scaffold(
      body: ProgramsScreen(state: s, onSetGoal: () {}, clock: () => now ?? _week1),
    ),
  ));
  await tester.pumpAndSettle();
  return s;
}

void main() {
  test('backend JSON round-trips through the models', () {
    final plan = loadPlan();
    expect(plan.blocks.length, 3);
    expect(plan.phaseNumber, 1);
    expect(plan.goalIds, ['goal-a', 'goal-b']);
    expect(plan.totalWeeks, 12);
    final detail = plan.blocks.first.detail!;
    expect(detail.days.length, 2);
    expect(detail.days.first.exercises.first.weeks.length, 4);
    final again = BlockDetail.fromJson(
        jsonDecode(jsonEncode(detail.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(again.toJson()), jsonEncode(detail.toJson()));
    expect(detail.days.first.exercises.first.weeks.first.scheme, '4 x 3');
    expect(detail.days.first.exercises[3].weeks.first.scheme, '15 min Zone 2');
    expect(plan.blocks[1].detail, isNull);
  });

  test('current week is computed from the start date', () {
    final plan = loadPlan();
    expect(plan.currentWeek(DateTime(2026, 9, 14)), 1);
    expect(plan.currentWeek(DateTime(2026, 9, 20)), 1);
    expect(plan.currentWeek(DateTime(2026, 9, 21)), 2);
    expect(plan.currentWeek(DateTime(2026, 9, 10)), 1); // before start counts as week 1
    expect(plan.isComplete(DateTime(2026, 12, 6)), isFalse); // last day of week 12
    expect(plan.isComplete(DateTime(2026, 12, 7)), isTrue); // first day after
  });

  testWidgets('phone layout: one week at a time, no overflow', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Phase 1  ·  Week 1 of 12'), findsOneWidget);
    expect(find.text('Front Squat'), findsOneWidget);
    expect(find.text('4 x 3'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);

    await tester.tap(find.text('Wk 4'));
    await tester.pumpAndSettle();
    expect(find.text('Backoff 1x3 @ 90% top set'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide layout: all four weeks side by side', (tester) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(tester.takeException(), isNull);
    expect(find.text('Wk 1'), findsWidgets);
    expect(find.text('Wk 4'), findsWidgets);
    expect(find.text('4 x 5'), findsWidgets);
  });

  testWidgets('unbuilt block offers build, and only after the previous one', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Block 3'));
    await tester.pumpAndSettle();
    expect(find.text('Build Block 2 first.'), findsOneWidget);
    await tester.tap(find.text('Block 2'));
    await tester.pumpAndSettle();
    expect(find.text('Build Block 2 workouts'), findsOneWidget);
  });

  testWidgets('opens on the current block and week, and marks them', (tester) async {
    await _pump(tester, now: _weekN(6)); // week 6 = block 2, second week
    expect(find.text('Phase 1  ·  Week 6 of 12'), findsOneWidget);
    expect(find.text('Block 2 •'), findsOneWidget);
    expect(find.text('Block 1'), findsOneWidget);
    // Block 2 isn't built, so we land on its build prompt.
    expect(find.text('Build Block 2 workouts'), findsOneWidget);

    await tester.tap(find.text('Block 1'));
    await tester.pumpAndSettle();
    expect(find.text('Block 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a mid-block week is pre-selected and marked', (tester) async {
    await _pump(tester, now: _weekN(3));
    expect(find.text('Wk 3 •'), findsOneWidget);
    expect(find.text('72-74%'), findsOneWidget); // week 3 front squat effort
  });

  testWidgets('tapping an exercise opens the editor with its values', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Front Squat'));
    await tester.pumpAndSettle();
    expect(find.text('Edit exercise'), findsOneWidget);
    expect(find.text('Week 1'), findsOneWidget);
    expect(find.text('Copy week 1 to all'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing an exercise and saving updates the program', (tester) async {
    final state = await _pump(tester);
    await tester.tap(find.text('Front Squat'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Safety Bar Squat');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(state.saved.length, 1);
    final ex = state.saved.values.single.days.first.exercises.first;
    expect(ex.name, 'Safety Bar Squat');
    expect(ex.weeks.length, 4);
    expect(ex.weeks.first.scheme, '4 x 3');
    expect(find.text('Safety Bar Squat'), findsOneWidget);
  });

  group('phase complete', () {
    testWidgets('offers the next phase after week 12', (tester) async {
      final state = await _pump(tester, now: _weekN(13));
      expect(find.text('Phase 1 complete'), findsOneWidget);
      expect(find.text('Phase 1  ·  Week 13 of 12'), findsNothing);
      // No block is marked as current once the phase is over.
      expect(find.textContaining('•'), findsNothing);

      await tester.tap(find.text('Plan next phase'));
      await tester.pumpAndSettle();
      expect(find.text('Plan Phase 2'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Plan next phase'),
      ));
      await tester.pumpAndSettle();
      expect(state.nextPhaseCalls, 1);
      expect(state.nextPhaseLevel, 'intermediate'); // prefilled from the profile
    });

    testWidgets('cancelling the dialog plans nothing', (tester) async {
      final state = await _pump(tester, now: _weekN(13));
      await tester.tap(find.text('Plan next phase'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.nextPhaseCalls, 0);
    });

    testWidgets('no banner mid-phase', (tester) async {
      await _pump(tester, now: _weekN(12));
      expect(find.text('Phase 1 complete'), findsNothing);
      expect(find.text('Phase 1  ·  Week 12 of 12'), findsOneWidget);
    });
  });

  group('rebuild block', () {
    testWidgets('asks first, and keeping the block rebuilds nothing', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.text('Rebuild block'));
      await tester.pumpAndSettle();
      expect(find.text('Rebuild Block 1?'), findsOneWidget);
      expect(find.textContaining('including any edits you made'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(state.builds, isEmpty);
      expect(find.text('Front Squat'), findsOneWidget);
    });

    testWidgets('confirming rebuilds with regenerate on', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.text('Rebuild block'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rebuild'));
      await tester.pumpAndSettle();
      expect(state.builds, ['00000000-0000-0000-0000-000000000001|regenerate=true']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('warns about completed weeks mid-block', (tester) async {
      await _pump(tester, now: _weekN(3));
      await tester.tap(find.text('Rebuild block'));
      await tester.pumpAndSettle();
      expect(find.textContaining('weeks you have already completed'), findsOneWidget);
    });
  });

  group('adjust plan', () {
    testWidgets('propose, review, apply', (tester) async {
      final state = await _pump(tester, now: _weekN(3));
      await tester.tap(find.text('Adjust plan'));
      await tester.pumpAndSettle();
      expect(find.text('Adjust Block 1'), findsOneWidget);
      expect(find.text('Weeks 1-2 are already done and will not change.'), findsOneWidget);

      // Can't ask until something is typed.
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Ask coach')).onPressed,
          isNull);
      await tester.enterText(find.byType(TextField).first, 'My left shoulder hurts overhead');
      await tester.pump();
      await tester.tap(find.text('Ask coach'));
      await tester.pumpAndSettle();

      expect(state.adjustRequests, ['My left shoulder hurts overhead|injury=true|done=2']);
      expect(find.text("Your coach's proposal"), findsOneWidget);
      expect(find.text('Swapped the squat to spare your shoulder.'), findsOneWidget);
      expect(find.text('Day 1: Front Squat -> Safety Bar Squat'), findsOneWidget);
      // Nothing saved until approved.
      expect(state.saved, isEmpty);

      await tester.tap(find.text('Apply changes'));
      await tester.pumpAndSettle();
      expect(state.saved.length, 1);
      expect(state.saved.values.single.days.first.exercises.first.name, 'Safety Bar Squat');
      expect(find.text('Program updated'), findsOneWidget);
      expect(find.text('Safety Bar Squat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('discarding saves nothing', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.text('Adjust plan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'No sled at my gym');
      await tester.pump();
      await tester.tap(find.byType(Switch)); // not an injury
      await tester.pump();
      await tester.tap(find.text('Ask coach'));
      await tester.pumpAndSettle();
      expect(state.adjustRequests, ['No sled at my gym|injury=false|done=0']);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(state.saved, isEmpty);
      expect(find.text('Front Squat'), findsOneWidget);
    });

    testWidgets('shows the error and lets the user retry when the coach fails', (tester) async {
      final state = TestState()..proposal = (_) => throw ApiException('Coach unavailable');
      await _pump(tester, state: state);
      await tester.tap(find.text('Adjust plan'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Knee pain');
      await tester.pump();
      await tester.tap(find.text('Ask coach'));
      await tester.pumpAndSettle();
      expect(find.text('Coach unavailable'), findsOneWidget);
      expect(find.text('Ask coach'), findsOneWidget); // back on the input step
      expect(state.saved, isEmpty);
    });

    testWidgets('is disabled for a block that is already finished', (tester) async {
      await _pump(tester, now: _weekN(6)); // block 1 (weeks 1-4) is over
      await tester.tap(find.text('Block 1'));
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Adjust plan'));
      expect(button.onPressed, isNull);
    });

    testWidgets('sheet fits a small phone with the keyboard up', (tester) async {
      await _pump(tester, size: const Size(360, 640));
      await tester.tap(find.text('Adjust plan'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
