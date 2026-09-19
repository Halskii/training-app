import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiClient();
  final _goal = TextEditingController();
  final _trainingAge = TextEditingController();
  String _kind = 'long_term';
  bool _loading = false;
  String? _error;
  Macrocycle? _plan;

  @override
  void initState() {
    super.initState();
    _loadLatest();
  }

  Future<void> _loadLatest() async {
    try {
      final plan = await _api.latestMacrocycle();
      if (mounted) setState(() => _plan = plan);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _generate() async {
    if (_goal.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await _api.planMacrocycle(
        goalDescription: _goal.text.trim(),
        goalKind: _kind,
        trainingAgeYears: double.tryParse(_trainingAge.text),
      );
      setState(() => _plan = plan);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your 12-week plan'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: _goal,
                decoration: const InputDecoration(
                  labelText: 'Your goal',
                  hintText: 'e.g. Squat 405 lb, or powerlifting meet in 12 weeks',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _kind,
                      decoration: const InputDecoration(labelText: 'Goal type'),
                      items: const [
                        DropdownMenuItem(value: 'long_term', child: Text('Long-term')),
                        DropdownMenuItem(value: 'phase', child: Text('This training phase')),
                        DropdownMenuItem(value: 'competition', child: Text('Competition')),
                      ],
                      onChanged: (v) => setState(() => _kind = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _trainingAge,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Years training'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _generate,
                child: Text(_loading ? 'Your coach is planning...' : 'Plan my 12 weeks'),
              ),
              if (_loading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              if (_plan != null) ...[
                const SizedBox(height: 24),
                for (final b in _plan!.blocks) _BlockCard(block: b),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  final BlockSkeleton block;
  const _BlockCard({required this.block});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${block.phase.toUpperCase()}  ·  Weeks ${block.weekStart}-${block.weekEnd}',
              style: t.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Volume: ${block.volumeTrend}'),
            Text('Intensity: ${block.intensityTrend}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [for (final m in block.movementFocus) Chip(label: Text(m))],
            ),
            const SizedBox(height: 8),
            Text(block.rationale, style: t.bodyMedium),
          ],
        ),
      ),
    );
  }
}
