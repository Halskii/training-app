import 'dart:convert';
import 'dart:io';

import 'package:training_app/api.dart';
import 'package:training_app/app_state.dart';

Map<String, dynamic> fixtureJson() =>
    jsonDecode(File('test/fixtures/macrocycle_view.json').readAsStringSync())
        as Map<String, dynamic>;

Macrocycle loadPlan() => Macrocycle.fromJson(fixtureJson());

Athlete makeAthlete({
  List<Map<String, dynamic>>? goals,
  List<Map<String, dynamic>>? injuries,
  int days = 4,
}) =>
    Athlete.fromJson({
      'training_level': 'intermediate',
      'training_age_years': 4,
      'training_days_per_week': days,
      'goals': goals ??
          [
            {
              'id': 'goal-a',
              'description': 'Squat 455 lb',
              'kind': 'phase',
              'target_date': null,
              'competition_events': null,
            },
            {
              'id': 'goal-b',
              'description': 'Win a strongman meet',
              'kind': 'competition',
              'target_date': '2027-03-01',
              'competition_events': ['Log press', 'Yoke'],
            },
          ],
      'injury_flags': injuries ?? [],
    });

/// AppState that never touches the network: it records calls and applies changes in memory.
class TestState extends AppState {
  final json = fixtureJson();

  final saved = <String, BlockDetail>{};
  final addedGoals = <String>[];
  final updatedGoals = <String>[];
  final deletedGoals = <String>[];
  final resolvedInjuries = <String>[];
  final adjustRequests = <String>[];
  int generateCalls = 0;
  int nextPhaseCalls = 0;
  String? nextPhaseLevel;

  /// What proposeAdjustment returns; tests can replace it.
  AdjustProposal Function(Block block)? proposal;

  TestState() {
    loading = false;
    plan = loadPlan();
    athlete = makeAthlete();
  }

  final builds = <String>[];

  @override
  Future<void> buildBlock(String blockId, {bool regenerate = false}) async {
    builds.add('$blockId|regenerate=$regenerate');
  }

  @override
  Future<bool> saveBlockDetail(String blockId, BlockDetail detail) async {
    saved[blockId] = detail;
    final blocks = (json['blocks'] as List).cast<Map<String, dynamic>>();
    blocks.firstWhere((b) => b['block_id'] == blockId)['detail'] = detail.toJson();
    plan = Macrocycle.fromJson(json);
    notifyListeners();
    return true;
  }

  @override
  Future<AdjustProposal> proposeAdjustment(
    String blockId, {
    required String request,
    required bool isInjury,
    required int completedWeeks,
  }) async {
    adjustRequests.add('$request|injury=$isInjury|done=$completedWeeks');
    final block = plan!.blocks.firstWhere((b) => b.id == blockId);
    return proposal?.call(block) ?? _defaultProposal(block);
  }

  AdjustProposal _defaultProposal(Block block) {
    final d = block.detail!.copy();
    d.days.first.exercises.first.name = 'Safety Bar Squat';
    return AdjustProposal.fromJson({
      'detail': d.toJson(),
      'summary': 'Swapped the squat to spare your shoulder.',
      'changes': ['Day 1: Front Squat -> Safety Bar Squat'],
    });
  }

  @override
  Future<void> addGoal({
    required String description,
    required String kind,
    DateTime? targetDate,
    List<String> events = const [],
  }) async {
    addedGoals.add('$description|$kind|${targetDate?.year}|${events.join(",")}');
  }

  @override
  Future<void> updateGoal(
    String id, {
    required String description,
    required String kind,
    DateTime? targetDate,
    List<String> events = const [],
  }) async {
    updatedGoals.add('$id|$description|$kind');
  }

  @override
  Future<void> deleteGoal(String id) async => deletedGoals.add(id);

  @override
  Future<void> resolveInjury(String id) async => resolvedInjuries.add(id);

  @override
  Future<bool> generate({
    required String trainingLevel,
    double? trainingAgeYears,
    int? trainingDaysPerWeek,
    String? injuries,
  }) async {
    generateCalls++;
    return true;
  }

  @override
  Future<bool> planNextPhase({
    required String trainingLevel,
    int? trainingDaysPerWeek,
  }) async {
    nextPhaseCalls++;
    nextPhaseLevel = trainingLevel;
    return true;
  }
}
