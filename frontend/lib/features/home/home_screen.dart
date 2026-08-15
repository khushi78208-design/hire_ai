import 'package:flutter/material.dart';
import '../../core/storage/token_storage.dart';
import '../auth/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _role;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await TokenStorage.getRole();
    if (!mounted) return;
    setState(() {
      _role = role;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isHr = _role == 'hr';

    return Scaffold(
      appBar: AppBar(
        title: Text(isHr ? 'Recruiter dashboard' : 'Find jobs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _logout,
          ),
        ],
      ),
      // The whole point of this screen right now: prove the role from the
      // JWT actually drives what the user sees.
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isHr ? Icons.business_center : Icons.work_outline,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                isHr ? 'Welcome, recruiter' : 'Welcome',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                isHr
                    ? 'Post vacancies and review AI-matched candidates here.'
                    : 'Browse openings and track your applications here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
              const SizedBox(height: 32),
              Chip(label: Text('Signed in as: ${_role ?? "unknown"}')),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: isHr
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.work_outline),
                  label: 'Vacancies',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline),
                  label: 'Candidates',
                ),
              ]
            : const [
                NavigationDestination(icon: Icon(Icons.search), label: 'Jobs'),
                NavigationDestination(
                  icon: Icon(Icons.description_outlined),
                  label: 'Applications',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  label: 'Profile',
                ),
              ],
      ),
    );
  }
}
