import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:training_app/screens/goals_screen.dart';

import 'test_helpers.dart';

Future<TestState> _pump(
  WidgetTester tester, {
  TestState? state,
  VoidCallback? onPlanCreated,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final s = state ?? TestState();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(colorSchemeSeed: const Color(0xFF1F3A5F), brightness: Brightness.dark),
    home: Scaffold(
      body: GoalsScreen(state: s, onPlanCreated: onPlanCreated ?? () {}),
    ),
  ));
  await tester.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('lists goals with details and an Add goal button', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Squat 455 lb'), findsOneWidget);
    expect(find.text('Win a strongman meet'), findsOneWidget);
    expect(find.textContaining('Mar 1, 2027'), findsOneWidget);
    expect(find.textContaining('Log press, Yoke'), findsOneWidget);
    expect(find.text('Add goal'), findsOneWidget);
    // Plan settings were prefilled from the saved profile.
    expect(find.text('Intermediate'), findsOneWidget);
    expect(find.text('4 days'), findsOneWidget);
  });

  testWidgets('training days are limited to 2-5', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('days-4')));
    await tester.pumpAndSettle();
    for (final d in [2, 3, 4, 5]) {
      expect(find.text('$d days'), findsWidgets, reason: '$d days should be offered');
    }
    expect(find.text('6 days'), findsNothing);
    expect(find.text('7 days'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a saved value above the cap is clamped instead of crashing', (tester) async {
    final state = TestState()..athlete = makeAthlete(days: 7);
    await _pump(tester, state: state);
    expect(find.text('5 days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no goals: plan button is disabled with a hint', (tester) async {
    final state = TestState()
      ..plan = null
      ..athlete = makeAthlete(goals: []);
    await _pump(tester, state: state);
    expect(find.textContaining('No goals yet'), findsOneWidget);
    expect(find.text('Add a goal first.'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Plan my 12 weeks'));
    expect(button.onPressed, isNull);
  });

  group('add / edit / remove', () {
    testWidgets('add a competition goal with a date and events', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.text('Add goal'));
      await tester.pumpAndSettle();
      expect(find.text('Add goal'), findsNWidgets(2)); // button + sheet title

      // Saving empty is rejected.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Describe your goal first'), findsOneWidget);
      expect(state.addedGoals, isEmpty);

      await tester.enterText(find.widgetWithText(TextField, 'Your goal'), 'Win Nationals');
      await tester.tap(find.byKey(const ValueKey('kind-long_term')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Competition').last);
      await tester.pumpAndSettle();
      expect(find.text('Events (optional)'), findsOneWidget); // only for competitions
      await tester.enterText(find.widgetWithText(TextField, 'Events (optional)'), 'Log press, Yoke, ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(state.addedGoals, ['Win Nationals|competition|null|Log press,Yoke']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('edit opens prefilled and saves changes', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit goal'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Squat 455 lb'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Squat 455 lb'), 'Squat 500 lb');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(state.updatedGoals, ['goal-a|Squat 500 lb|phase']);
    });

    testWidgets('remove asks first, and cancelling keeps the goal', (tester) async {
      final state = await _pump(tester);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this goal?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.deletedGoals, isEmpty);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(state.deletedGoals, ['goal-a']);
    });
  });

  group('creating a plan', () {
    testWidgets('warns before replacing an existing program', (tester) async {
      var created = 0;
      final state = await _pump(tester, onPlanCreated: () => created++);
      await tester.tap(find.text('Create new plan'));
      await tester.pumpAndSettle();
      expect(find.text('Replace your current program?'), findsOneWidget);
      expect(find.textContaining('any edits you made'), findsOneWidget);
      expect(find.textContaining('Adjust plan'), findsOneWidget);

      // Keeping the program does nothing.
      await tester.tap(find.text('Keep my program'));
      await tester.pumpAndSettle();
      expect(state.generateCalls, 0);
      expect(created, 0);

      await tester.tap(find.text('Create new plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace program'));
      await tester.pumpAndSettle();
      expect(state.generateCalls, 1);
      expect(created, 1);
    });

    testWidgets('no warning when there is no program yet', (tester) async {
      final state = TestState()..plan = null;
      var created = 0;
      await _pump(tester, state: state, onPlanCreated: () => created++);
      await tester.tap(find.text('Plan my 12 weeks'));
      await tester.pumpAndSettle();
      expect(find.text('Replace your current program?'), findsNothing);
      expect(state.generateCalls, 1);
      expect(created, 1);
    });

    testWidgets('flags when goals changed since the plan was built', (tester) async {
      final unchanged = await _pump(tester);
      expect(unchanged.goalsChangedSincePlan, isFalse);
      expect(find.text('Your goals changed'), findsNothing);

      final changed = TestState()
        ..athlete = makeAthlete(goals: [
          {
            'id': 'goal-c',
            'description': 'Deadlift 600',
            'kind': 'long_term',
            'target_date': null,
            'competition_events': null,
          },
        ]);
      await _pump(tester, state: changed);
      expect(changed.goalsChangedSincePlan, isTrue);
      expect(find.text('Your goals changed'), findsOneWidget);
    });
  });
}
