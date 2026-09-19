import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();

  Macrocycle? plan;
  Athlete? athlete;
  bool loading = true;
  bool planning = false;
  String? loadError;
  String? planError;
  String? blockError;
  final Set<String> _building = {};

  bool isBuilding(String blockId) => _building.contains(blockId);

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final planFuture = api.latestMacrocycle();
      final athleteFuture = api.athlete();
      plan = await planFuture;
      athlete = await athleteFuture;
      loadError = null;
    } catch (e) {
      loadError = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  /// True when the saved goals differ from the ones the current plan was built for.
  bool get goalsChangedSincePlan {
    final p = plan, a = athlete;
    if (p == null || a == null) return false;
    final planned = p.goalIds.toSet();
    final current = a.goals.map((g) => g.id).toSet();
    return planned.length != current.length || !planned.containsAll(current);
  }

  Future<void> _refreshAthlete() async {
    athlete = await api.athlete();
    notifyListeners();
  }

  Future<void> addGoal({
    required String description,
    required String kind,
    DateTime? targetDate,
    List<String> events = const [],
  }) async {
    await api.addGoal(
        description: description, kind: kind, targetDate: targetDate, events: events);
    await _refreshAthlete();
  }

  Future<void> updateGoal(
    String id, {
    required String description,
    required String kind,
    DateTime? targetDate,
    List<String> events = const [],
  }) async {
    await api.updateGoal(id,
        description: description, kind: kind, targetDate: targetDate, events: events);
    await _refreshAthlete();
  }

  Future<void> deleteGoal(String id) async {
    await api.deleteGoal(id);
    await _refreshAthlete();
  }

  Future<void> resolveInjury(String id) async {
    await api.resolveInjury(id);
    await _refreshAthlete();
  }

  /// Returns true if a new plan was created. Block 1's workouts then build in
  /// the background so they're ready when the user lands on Programs.
  Future<bool> generate({
    required String trainingLevel,
    double? trainingAgeYears,
    int? trainingDaysPerWeek,
    String? injuries,
  }) =>
      _createPlan(() => api.planMacrocycle(
            trainingLevel: trainingLevel,
            trainingAgeYears: trainingAgeYears,
            trainingDaysPerWeek: trainingDaysPerWeek,
            injuries: injuries,
          ));

  /// Plans the next 12-week phase from the latest one.
  Future<bool> planNextPhase({
    required String trainingLevel,
    int? trainingDaysPerWeek,
  }) =>
      _createPlan(() => api.planNextPhase(
            trainingLevel: trainingLevel,
            trainingDaysPerWeek: trainingDaysPerWeek,
          ));

  Future<bool> _createPlan(Future<Macrocycle> Function() create) async {
    planning = true;
    planError = null;
    notifyListeners();
    try {
      plan = await create();
      athlete = await api.athlete();
      unawaited(buildBlock(plan!.blocks.first.id));
      return true;
    } catch (e) {
      planError = e.toString();
      return false;
    } finally {
      planning = false;
      notifyListeners();
    }
  }

  /// Asks the coach to revise a block. Throws on failure. If it is an injury, the
  /// server records it up front, so the injury list is refreshed either way.
  Future<AdjustProposal> proposeAdjustment(
    String blockId, {
    required String request,
    required bool isInjury,
    required int completedWeeks,
  }) async {
    try {
      return await api.adjustBlock(blockId,
          request: request, isInjury: isInjury, completedWeeks: completedWeeks);
    } finally {
      if (isInjury) {
        try {
          await _refreshAthlete();
        } catch (_) {}
      }
    }
  }

  void _replaceBlock(Block updated) {
    final blocks = plan?.blocks;
    if (blocks == null) return;
    final i = blocks.indexWhere((b) => b.id == updated.id);
    if (i != -1) blocks[i] = updated;
  }

  /// Builds a block's workouts. With [regenerate], replaces workouts that already
  /// exist (the caller is responsible for warning about lost edits).
  Future<void> buildBlock(String blockId, {bool regenerate = false}) async {
    _building.add(blockId);
    blockError = null;
    notifyListeners();
    try {
      _replaceBlock(await api.buildBlock(blockId, regenerate: regenerate));
    } catch (e) {
      blockError = e.toString();
    } finally {
      _building.remove(blockId);
      notifyListeners();
    }
  }

  /// Saves an edited block. Returns true on success; on failure the shown
  /// program is left untouched and [blockError] is set.
  Future<bool> saveBlockDetail(String blockId, BlockDetail detail) async {
    blockError = null;
    try {
      _replaceBlock(await api.saveBlockDetail(blockId, detail));
      notifyListeners();
      return true;
    } catch (e) {
      blockError = e.toString();
      notifyListeners();
      return false;
    }
  }
}
