import 'package:flutter/material.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import '../../main.dart';
import '../agent/agent_chat.dart';
import '../assessment/assessment_service.dart';
import '../assessment/take_test_screen.dart';
import '../auth/auth_service.dart';
import '../dashboard/dashboard_screen.dart';
import '../jobs/applicants_screen.dart';
import '../jobs/create_job_screen.dart';
import '../jobs/job_service.dart';
import '../jobs/jobs_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _role;
  String? _name;
  bool _loading = true;
  int _index = 0;

  // Set when the recruiter taps a number on the dashboard, so the
  // candidates tab opens already filtered instead of showing everything.
  String? _pendingJobId;
  String? _pendingStatus;

  // Bumping these rebuilds a tab so it reflects what just happened
  // elsewhere in the app.
  int _jobsVersion = 0;
  int _dashboardVersion = 0;

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

    // The drawer header needs a name; the token only carries the role.
    final name = await AuthService.currentName();
    if (mounted) setState(() => _name = name);
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
            DashboardScreen(
              key: ValueKey('dash-$_dashboardVersion'),
              onDrillDown: _drillDown,
            ),
            JobsListScreen(key: ValueKey('jobs-$_jobsVersion'), isHr: true),
            ApplicantsScreen(
              initialJobId: _pendingJobId,
              initialStatus: _pendingStatus,
            ),
          ]
        : [const JobsListScreen(isHr: false), const _MyApplicationsTab()];

    final titles = isHr
        ? ['Dashboard', 'Vacancies', 'Candidates']
        : ['Find jobs', 'My applications'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          // Lives here rather than as a second FAB — two floating buttons
          // in one corner collide.
          if (isHr && _index == 1)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New vacancy',
              onPressed: () async {
                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateJobScreen()),
                );
                if (created == true) setState(() => _jobsVersion++);
              },
            ),
        ],
      ),
      drawer: AppDrawer(
        name: _name ?? 'You',
        subtitle: isHr ? 'Recruiter' : 'Candidate',
        role: _role ?? '',
        selectedIndex: _index,
        onSelect: (i) => setState(() {
          _index = i;
          if (i == 0 && isHr) _dashboardVersion++;
          if (i != 2) {
            _pendingJobId = null;
            _pendingStatus = null;
          }
        }),
        items: isHr
            ? const [
                DrawerItem(
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  index: 0,
                ),
                DrawerItem(
                  icon: Icons.work_outline,
                  label: 'Vacancies',
                  index: 1,
                ),
                DrawerItem(
                  icon: Icons.people_outline,
                  label: 'Candidates',
                  index: 2,
                ),
              ]
            : const [
                DrawerItem(icon: Icons.search, label: 'Find jobs', index: 0),
                DrawerItem(
                  icon: Icons.description_outlined,
                  label: 'My applications',
                  index: 1,
                ),
              ],
        secondaryItems: [
          DrawerItem(
            icon: Icons.logout,
            label: 'Sign out',
            badgeColor: StatusColors.rejected,
            onTap: _logout,
          ),
        ],
      ),
      body: pages[_index],
      floatingActionButton: isHr
          ? FloatingActionButton(
              onPressed: () => AgentChatSheet.show(
                context,
                onJobCreated: () => setState(() => _jobsVersion++),
              ),
              tooltip: 'Assistant',
              child: const Icon(Icons.auto_awesome),
            )
          : null,
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
  List<Map<String, dynamic>> _tests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await JobService.myApplications();
    final tests = await AssessmentService.mine();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      // Anything still to sit goes above the application list — it is the
      // one thing here with a deadline attached.
      _tests = tests.where((t) => t['status'] != 'submitted').toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_apps.isEmpty && _tests.isEmpty) {
      return const _PlaceholderTab(
        icon: Icons.description_outlined,
        title: 'No applications yet',
        message: 'Jobs you apply to will show up here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          for (final t in _tests) _PendingTestCard(test: t, onDone: _load),
          for (final a in _apps) _ApplicationCard(app: a),
        ],
      ),
    );
  }
}

class _PendingTestCard extends StatelessWidget {
  final Map<String, dynamic> test;
  final VoidCallback onDone;

  const _PendingTestCard({required this.test, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assessment = test['assessments'] as Map<String, dynamic>?;
    final job = assessment?['jobs'] as Map<String, dynamic>?;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        // Outlined in the accent colour so it reads as an action, not
        // another status card.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: theme.colorScheme.primary),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.quiz_outlined,
                    size: 19,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    'Assessment pending',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              Text(
                assessment?['title'] ?? 'Assessment',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: Space.xs),
              Text(
                '${job?['title'] ?? 'Role'} · '
                '${assessment?['duration_min'] ?? 20} minutes',
                style: TextStyle(fontSize: 13, color: theme.hintColor),
              ),
              const SizedBox(height: Space.lg),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () async {
                    final done = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TakeTestScreen(attemptId: test['id'] as String),
                      ),
                    );
                    if (done == true) onDone();
                  },
                  child: const Text('Start test'),
                ),
              ),
            ],
          ),
        ),
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
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: theme.hintColor),
            const SizedBox(height: Space.lg),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.xs + 2),
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
