import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api.dart';
import '../app_state.dart';

class ProfileScreen extends StatelessWidget {
  final AppState state;
  const ProfileScreen({super.key, required this.state});

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _resolve(BuildContext context, InjuryItem injury) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.resolveInjury(injury.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = (user?.userMetadata?['display_name'] as String?) ?? '';
    final t = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final a = state.athlete;
        final years = a?.trainingAgeYears;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: t.headlineSmall,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (name.isNotEmpty) Text(name, style: t.titleLarge),
                          Text(user?.email ?? ''),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.trending_up),
                        title: const Text('Training level'),
                        trailing: Text(a?.trainingLevel == null
                            ? 'Not set'
                            : _capitalize(a!.trainingLevel!)),
                      ),
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Years training'),
                        trailing: Text(years == null
                            ? 'Not set'
                            : (years == years.roundToDouble()
                                ? '${years.toInt()}'
                                : '$years')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Injuries and concerns', style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Your coach plans around these. Mark one resolved once it has healed.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 8),
                if (a == null || a.injuries.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.check_circle_outline),
                      title: Text('Nothing active'),
                    ),
                  )
                else
                  for (final injury in a.injuries)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.healing_outlined),
                        title: Text(injury.note),
                        subtitle: Text(injury.area),
                        trailing: TextButton(
                          onPressed: () => _resolve(context, injury),
                          child: const Text('Resolved'),
                        ),
                      ),
                    ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
