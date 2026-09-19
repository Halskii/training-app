import 'package:flutter/material.dart';

import '../app_state.dart';
import 'coach_screen.dart';
import 'goals_screen.dart';
import 'profile_screen.dart';
import 'programs_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _goalsTab = 0;
  static const _programsTab = 1;
  static const _titles = ['Goals', 'Programs', 'Coach', 'Profile'];

  final _state = AppState();
  int _index = _programsTab;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _state.load();
    // First-time users have no plan yet, so start them where they can make one.
    if (mounted && _state.plan == null && _state.loadError == null) {
      setState(() => _index = _goalsTab);
    }
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: IndexedStack(
        index: _index,
        children: [
          GoalsScreen(
            state: _state,
            onPlanCreated: () => setState(() => _index = _programsTab),
          ),
          ProgramsScreen(
            state: _state,
            onSetGoal: () => setState(() => _index = _goalsTab),
          ),
          const CoachScreen(),
          ProfileScreen(state: _state),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Goals',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Programs',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Coach',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
