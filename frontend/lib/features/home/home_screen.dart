import 'package:flutter/material.dart';
import '../../core/storage/token_storage.dart';
import '../auth/auth_service.dart';
import '../jobs/jobs_list_screen.dart';
import '../jobs/job_service.dart';
import '../jobs/applicants_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _role;
  bool _loading = true;
  int _index = 0;

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

    final pages = isHr
        ? [const JobsListScreen(isHr: true), ApplicantsScreen()]
        : [const JobsListScreen(isHr: false), const _MyApplicationsTab()];

    final titles = isHr
        ? ['My vacancies', 'Candidates']
        : ['Find jobs', 'My applications'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _logout,
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: isHr
            ? const [
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
              ],
      ),
    );
  }
}

class _MyApplicationsTab extends StatefulWidget {
  const _MyApplicationsTab();

  @override
  State<_MyApplicationsTab> createState() => _MyApplicationsTabState();
}

class _MyApplicationsTabState extends State<_MyApplicationsTab> {
  List<Map<String, dynamic>> _apps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await JobService.myApplications();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_apps.isEmpty) {
      return const _PlaceholderTab(
        icon: Icons.description_outlined,
        title: 'No applications yet',
        message: 'Jobs you apply to will show up here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _apps.length,
        itemBuilder: (context, i) {
          final app = _apps[i];
          final job = app['jobs'] as Map<String, dynamic>?;
          final status = app['status'] ?? 'applied';

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: Text(
                job?['title'] ?? 'Job',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(job?['location'] ?? 'Remote'),
              ),
              trailing: Chip(
                label: Text(
                  status.toString().toUpperCase(),
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _PlaceholderTab({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: theme.hintColor),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}
