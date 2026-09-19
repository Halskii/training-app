import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

class BlockSkeleton {
  final String phase;
  final int weekStart;
  final int weekEnd;
  final String volumeTrend;
  final String intensityTrend;
  final List<String> movementFocus;
  final String rationale;

  BlockSkeleton.fromJson(Map<String, dynamic> j)
      : phase = j['phase'],
        weekStart = j['week_start'],
        weekEnd = j['week_end'],
        volumeTrend = j['volume_trend'],
        intensityTrend = j['intensity_trend'],
        movementFocus = List<String>.from(j['movement_focus']),
        rationale = j['rationale'];
}

class Macrocycle {
  final String id;
  final List<BlockSkeleton> blocks;

  Macrocycle.fromJson(Map<String, dynamic> j)
      : id = j['macrocycle_id'],
        blocks = (j['blocks'] as List)
            .map((b) => BlockSkeleton.fromJson(b as Map<String, dynamic>))
            .toList();
}

class ApiClient {
  Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Macrocycle> planMacrocycle({
    required String goalDescription,
    required String goalKind,
    double? trainingAgeYears,
  }) async {
    final res = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/programs/macrocycle'),
          headers: _headers,
          body: jsonEncode({
            'goal_description': goalDescription,
            'goal_kind': goalKind,
            'training_age_years': trainingAgeYears,
          }),
        )
        .timeout(const Duration(seconds: 180));

    if (res.statusCode != 200) {
      throw Exception('Backend error ${res.statusCode}: ${res.body}');
    }
    return Macrocycle.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Macrocycle?> latestMacrocycle() async {
    final res = await http
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/programs/macrocycle/latest'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('Backend error ${res.statusCode}: ${res.body}');
    }
    return Macrocycle.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
