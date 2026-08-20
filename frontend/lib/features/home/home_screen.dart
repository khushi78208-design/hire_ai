import 'package:flutter/material.dart';
import '../../core/storage/token_storage.dart';
import '../../main.dart';
import '../auth/auth_service.dart';
import '../dashboard/dashboard_screen.dart';
import '../jobs/jobs_list_screen.dart';
import '../jobs/job_service.dart';
import '../jobs/applicants_screen.dart';
import '../../core/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _role;
  bool _loading = true;
  int _index = 0;

  // Set when the recruiter taps a number on the dashboard, so the
  // candidates tab opens already filtered instead of showing everything.
  String? _pendingJobId;
  String? _pendingStatus;

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
    // Repaint the whole app in this role's palette.
    HireAIApp.of(context)?.setRole(role);
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    HireAIApp.of(context)?.setRole(null);
    Navigator.of(context).pushReplacementNamed('/login');
  }

  void _drillDown(String? jobId, String? status) {
    setState(() {
      _pendingJobId = jobId;
      _pendingStatus = status;
      _index = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isHr = _role == 'hr' || _role == 'admin';

    final pages = isHr
        ? [
            DashboardScreen(onDrillDown: _drillDown),
            const JobsListScreen(isHr: true),
            ApplicantsScreen(
              initialJobId: _pendingJobId,
              initialStatus: _pendingStatus,
            ),
          ]
        : [const JobsListScreen(isHr: false), const _MyApplicationsTab()];

    final titles = isHr
        ? ['Dashboard', 'My vacancies', 'Candidates']
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
        onDestinationSelected: (i) => setState(() {
          _index = i;
          if (i != 2) {
            _pendingJobId = null;
            _pendingStatus = null;
          }
        }),
        destinations: isHr
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.work_outline),
                  selectedIcon: Icon(Icons.work),
                  label: 'Vacancies',
                ),
                NavigationDestination(
                  icon: Icon(Icons.people_outline),
                  selectedIcon: Icon(Icons.people),
                  label: 'Candidates',
                ),
              ]
            : const [
                NavigationDestination(icon: Icon(Icons.search), label: 'Jobs'),
                NavigationDestination(
                  icon: Icon(Icons.description_outlined),
                  selectedIcon: Icon(Icons.description),
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
        padding: const EdgeInsets.all(Space.lg),
        itemCount: _apps.length,
        itemBuilder: (context, i) => _ApplicationCard(app: _apps[i]),
      ),
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  final Map<String, dynamic> app;

  const _ApplicationCard({required this.app});

  /// Where this application sits on the pipeline. Rejected is off the
  /// track entirely, so it returns -1 and the stepper is replaced.
  int _stage(String status) => switch (status) {
    'shortlisted' => 1,
    'interview' => 2,
    'selected' => 3,
    'rejected' => -1,
    _ => 0,
  };

  String _message(String status) => switch (status) {
    'shortlisted' => 'Your profile was shortlisted. The team will be in touch.',
    'on_hold' => 'Your application is under consideration.',
    'interview' => 'You have moved to the interview stage.',
    'selected' => 'Congratulations — you have been selected.',
    'rejected' =>
      'You were not selected for this role. Keep applying — this one '
          'is not a reflection of your abilities.',
    _ => 'Your application has been received.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final job = app['jobs'] as Map<String, dynamic>?;
    final status = (app['status'] ?? 'applied').toString();
    final stage = _stage(status);
    final color = StatusColors.of(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job?['title'] ?? 'Job',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.xs,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      StatusColors.label(status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 14, color: theme.hintColor),
                  const SizedBox(width: Space.xs),
                  Text(
                    job?['location'] ?? 'Remote',
                    style: TextStyle(fontSize: 13, color: theme.hintColor),
                  ),
                ],
              ),

              const SizedBox(height: Space.lg),

              if (stage >= 0)
                _Stepper(stage: stage, color: color)
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    _message(status),
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),

              if (stage >= 0) ...[
                const SizedBox(height: Space.md),
                Text(
                  _message(status),
                  style: TextStyle(fontSize: 13, color: theme.hintColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int stage;
  final Color color;

  const _Stepper({required this.stage, required this.color});

  static const _labels = ['Applied', 'Shortlisted', 'Interview', 'Result'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = theme.dividerColor;

    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i <= stage ? color : Colors.transparent,
                  border: Border.all(
                    color: i <= stage ? color : inactive,
                    width: 1.5,
                  ),
                ),
                child: i <= stage
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: Space.xs),
              Text(
                _labels[i],
                style: TextStyle(
                  fontSize: 10.5,
                  color: i <= stage ? color : theme.hintColor,
                  fontWeight: i == stage ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
          if (i < _labels.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 18),
                color: i < stage ? color : inactive,
              ),
            ),
        ],
      ],
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
