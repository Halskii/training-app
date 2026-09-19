import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

/// One exercise's prescription for one week (one cell of the program sheet).
class WeekRx {
  int? sets;
  String? reps;
  String? effort;
  String? note;

  WeekRx({this.sets, this.reps, this.effort, this.note});

  WeekRx.fromJson(Map<String, dynamic> j)
      : sets = (j['sets'] as num?)?.toInt(),
        reps = j['reps'] as String?,
        effort = j['effort'] as String?,
        note = j['note'] as String?;

  Map<String, dynamic> toJson() =>
      {'sets': sets, 'reps': reps, 'effort': effort, 'note': note};

  /// "4 x 3", or just the reps text when there are no sets (e.g. "15 min Zone 2").
  String get scheme {
    final r = (reps ?? '').trim();
    if (sets != null && r.isNotEmpty) return '$sets x $r';
    if (r.isNotEmpty) return r;
    return sets != null ? '$sets sets' : '';
  }
}

class Exercise {
  String name;
  String? group;
  String? cue;
  List<WeekRx> weeks;

  Exercise({required this.name, this.group, this.cue, required this.weeks});

  Exercise.fromJson(Map<String, dynamic> j)
      : name = j['name'],
        group = j['group'] as String?,
        cue = j['cue'] as String?,
        weeks = (j['weeks'] as List)
            .map((w) => WeekRx.fromJson(w as Map<String, dynamic>))
            .toList();

  Map<String, dynamic> toJson() => {
        'name': name,
        'group': group,
        'cue': cue,
        'weeks': weeks.map((w) => w.toJson()).toList(),
      };
}

class WarmupSection {
  final String title;
  final String? prescription;
  final List<String> items;
  final String? notes;

  WarmupSection.fromJson(Map<String, dynamic> j)
      : title = j['title'],
        prescription = j['prescription'] as String?,
        items = List<String>.from(j['items']),
        notes = j['notes'] as String?;

  Map<String, dynamic> toJson() => {
        'title': title,
        'prescription': prescription,
        'items': items,
        'notes': notes,
      };
}

class DayPlan {
  int dayIndex;
  String title;
  final List<WarmupSection> warmup;
  final List<Exercise> exercises;

  DayPlan.fromJson(Map<String, dynamic> j)
      : dayIndex = j['day_index'],
        title = j['title'],
        warmup = (j['warmup'] as List? ?? [])
            .map((w) => WarmupSection.fromJson(w as Map<String, dynamic>))
            .toList(),
        exercises = (j['exercises'] as List)
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList();

  Map<String, dynamic> toJson() => {
        'day_index': dayIndex,
        'title': title,
        'warmup': warmup.map((w) => w.toJson()).toList(),
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };
}

class BlockDetail {
  final String phase;
  final int weekStart;
  final int weekEnd;
  final List<DayPlan> days;
  final String coachNote;

  BlockDetail.fromJson(Map<String, dynamic> j)
      : phase = j['phase'],
        weekStart = j['week_start'],
        weekEnd = j['week_end'],
        days = (j['days'] as List)
            .map((d) => DayPlan.fromJson(d as Map<String, dynamic>))
            .toList(),
        coachNote = (j['coach_note'] as String?) ?? '';

  Map<String, dynamic> toJson() => {
        'phase': phase,
        'week_start': weekStart,
        'week_end': weekEnd,
        'days': days.map((d) => d.toJson()).toList(),
        'coach_note': coachNote,
      };

  /// Deep copy, so edits can be made and discarded if saving fails.
  BlockDetail copy() =>
      BlockDetail.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
}

class Block {
  final String id;
  final String phase;
  final int weekStart;
  final int weekEnd;
  final String volumeTrend;
  final String intensityTrend;
  final List<String> movementFocus;
  final String rationale;
  final BlockDetail? detail;

  int get numWeeks => weekEnd - weekStart + 1;

  Block.fromJson(Map<String, dynamic> j)
      : id = j['block_id'],
        phase = j['phase'],
        weekStart = j['week_start'],
        weekEnd = j['week_end'],
        volumeTrend = j['volume_trend'],
        intensityTrend = j['intensity_trend'],
        movementFocus = List<String>.from(j['movement_focus']),
        rationale = j['rationale'],
        detail = j['detail'] == null
            ? null
            : BlockDetail.fromJson(j['detail'] as Map<String, dynamic>);
}

class Macrocycle {
  final String id;
  final String coachNote;
  final int phaseNumber;
  final DateTime? startDate;
  final List<String> goalIds;
  final List<Block> blocks;

  Macrocycle.fromJson(Map<String, dynamic> j)
      : id = j['macrocycle_id'],
        coachNote = (j['coach_note'] as String?) ?? '',
        phaseNumber = (j['phase_number'] as num?)?.toInt() ?? 1,
        startDate = j['start_date'] == null ? null : DateTime.parse(j['start_date']),
        goalIds = List<String>.from(j['goal_ids'] ?? const []),
        blocks = (j['blocks'] as List)
            .map((b) => Block.fromJson(b as Map<String, dynamic>))
            .toList();

  int get totalWeeks => blocks.isEmpty ? 12 : blocks.last.weekEnd;

  /// 1-based week of this phase on [now]. Before the start date counts as week 1.
  int currentWeek(DateTime now) {
    final s = startDate;
    if (s == null) return 1;
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(s.year, s.month, s.day))
        .inDays;
    return days < 0 ? 1 : days ~/ 7 + 1;
  }

  bool isComplete(DateTime now) => currentWeek(now) > totalWeeks;
}

class GoalItem {
  final String id;
  final String description;
  final String kind;
  final DateTime? targetDate;
  final List<String> events;

  GoalItem.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        description = j['description'],
        kind = j['kind'],
        targetDate = j['target_date'] == null ? null : DateTime.parse(j['target_date']),
        events = List<String>.from(j['competition_events'] ?? const []);
}

class InjuryItem {
  final String id;
  final String area;
  final String note;

  InjuryItem.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        area = j['area'],
        note = j['note'];
}

class AdjustProposal {
  final BlockDetail detail;
  final String summary;
  final List<String> changes;

  AdjustProposal.fromJson(Map<String, dynamic> j)
      : detail = BlockDetail.fromJson(j['detail'] as Map<String, dynamic>),
        summary = j['summary'],
        changes = List<String>.from(j['changes']);
}

class Athlete {
  static const reportedInjuryArea = 'Athlete-reported';

  final String? trainingLevel;
  final double? trainingAgeYears;
  final int? trainingDaysPerWeek;
  final List<GoalItem> goals;
  final List<InjuryItem> injuries;

  Athlete.fromJson(Map<String, dynamic> j)
      : trainingLevel = j['training_level'] as String?,
        trainingAgeYears = (j['training_age_years'] as num?)?.toDouble(),
        trainingDaysPerWeek = (j['training_days_per_week'] as num?)?.toInt(),
        goals = (j['goals'] as List)
            .map((g) => GoalItem.fromJson(g as Map<String, dynamic>))
            .toList(),
        injuries = (j['injury_flags'] as List)
            .cast<Map<String, dynamic>>()
            .where((f) => f['active'] == true && f['id'] != null)
            .map(InjuryItem.fromJson)
            .toList();

  /// The injury note entered when setting up a plan (prefills that form field).
  String? get reportedInjuries =>
      injuries.where((i) => i.area == reportedInjuryArea).map((i) => i.note).firstOrNull;
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  factory ApiException.from(http.Response res) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['detail'] is String) {
        return ApiException(body['detail'] as String);
      }
    } catch (_) {}
    return ApiException('Backend error ${res.statusCode}: ${res.body}');
  }

  @override
  String toString() => message;
}

class ApiClient {
  Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Map<String, dynamic> _json(http.Response res) {
    if (res.statusCode != 200) throw ApiException.from(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Macrocycle> _plan(
    String path, {
    required String trainingLevel,
    double? trainingAgeYears,
    int? trainingDaysPerWeek,
    String? injuries,
  }) async {
    final res = await http
        .post(
          _uri(path),
          headers: _headers,
          body: jsonEncode({
            'training_level': trainingLevel,
            'training_age_years': trainingAgeYears,
            'training_days_per_week': trainingDaysPerWeek,
            // null leaves the saved injury note alone; '' clears it.
            'injuries': injuries,
          }),
        )
        .timeout(const Duration(seconds: 180));
    return Macrocycle.fromJson(_json(res));
  }

  /// A brand-new plan from the saved goals (replaces the one shown).
  Future<Macrocycle> planMacrocycle({
    required String trainingLevel,
    double? trainingAgeYears,
    int? trainingDaysPerWeek,
    String? injuries,
  }) =>
      _plan('/programs/macrocycle',
          trainingLevel: trainingLevel,
          trainingAgeYears: trainingAgeYears,
          trainingDaysPerWeek: trainingDaysPerWeek,
          injuries: injuries);

  /// The next 12-week phase, built on the latest one.
  Future<Macrocycle> planNextPhase({
    required String trainingLevel,
    int? trainingDaysPerWeek,
  }) =>
      _plan('/programs/macrocycle/next',
          trainingLevel: trainingLevel, trainingDaysPerWeek: trainingDaysPerWeek);

  Map<String, dynamic> _goalBody(
          String description, String kind, DateTime? targetDate, List<String> events) =>
      {
        'description': description,
        'kind': kind,
        'target_date': targetDate?.toIso8601String().substring(0, 10),
        'competition_events': events,
      };

  Future<GoalItem> addGoal({
    required String description,
    required String kind,
    DateTime? targetDate,
    List<String> events = const [],
  }) async {
    final res = await http
        .post(_uri('/goals'),
            headers: _headers,
            body: jsonEncode(_goalBody(description, kind, targetDate, events)))
        .timeout(const Duration(seconds: 30));
    return GoalItem.fromJson(_json(res));
  }

  Future<GoalItem> updateGoal(
    String id, {
    required String description,
    required String kind,
    DateTime? targetDate,
    List<String> events = const [],
  }) async {
    final res = await http
        .put(_uri('/goals/$id'),
            headers: _headers,
            body: jsonEncode(_goalBody(description, kind, targetDate, events)))
        .timeout(const Duration(seconds: 30));
    return GoalItem.fromJson(_json(res));
  }

  Future<void> deleteGoal(String id) async {
    final res = await http
        .delete(_uri('/goals/$id'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    _json(res);
  }

  Future<void> resolveInjury(String id) async {
    final res = await http
        .post(_uri('/athlete/injuries/$id/resolve'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    _json(res);
  }

  /// Asks the coach to revise a built block. Returns a preview; nothing is saved.
  Future<AdjustProposal> adjustBlock(
    String blockId, {
    required String request,
    required bool isInjury,
    required int completedWeeks,
  }) async {
    final res = await http
        .post(
          _uri('/programs/blocks/$blockId/adjust'),
          headers: _headers,
          body: jsonEncode({
            'request': request,
            'is_injury': isInjury,
            'completed_weeks': completedWeeks,
          }),
        )
        .timeout(const Duration(seconds: 300));
    return AdjustProposal.fromJson(_json(res));
  }

  Future<Athlete> athlete() async {
    final res =
        await http.get(_uri('/athlete/me'), headers: _headers).timeout(const Duration(seconds: 30));
    return Athlete.fromJson(_json(res));
  }

  Future<Macrocycle?> latestMacrocycle() async {
    final res = await http
        .get(_uri('/programs/macrocycle/latest'), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 404) return null;
    return Macrocycle.fromJson(_json(res));
  }

  Future<Block> buildBlock(String blockId, {bool regenerate = false}) async {
    final res = await http
        .post(
          _uri('/programs/blocks/$blockId/generate${regenerate ? '?regenerate=true' : ''}'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 300));
    return Block.fromJson(_json(res));
  }

  Future<Block> saveBlockDetail(String blockId, BlockDetail detail) async {
    final res = await http
        .put(
          _uri('/programs/blocks/$blockId/detail'),
          headers: _headers,
          body: jsonEncode(detail.toJson()),
        )
        .timeout(const Duration(seconds: 30));
    return Block.fromJson(_json(res));
  }
}
