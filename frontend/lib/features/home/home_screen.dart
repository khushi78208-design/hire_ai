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
    HireAIApp.of(context)?.setRole(role);

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

  /// Keyed by application id so each card knows whether a test is part of
  /// its pipeline, and whether it has been sat.
  Map<String, Map<String, dynamic>> _testsByApp = {};

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
      _testsByApp = {
        for (final t in tests)
          if (t['application_id'] != null) (t['application_id'] as String): t,
      };
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

    // A test still to sit is the only thing here with a clock on it, so it
    // goes above the pipeline cards.
    final pending = _testsByApp.values
        .where((t) => t['status'] != 'submitted')
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          for (final t in pending) _PendingTestCard(test: t, onDone: _load),
          for (final a in _apps)
            _ApplicationCard(app: a, test: _testsByApp[a['id']]),
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
    final minutes = assessment?['duration_min'] ?? 20;

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
                '${job?['title'] ?? 'Role'} · $minutes minutes',
                style: TextStyle(fontSize: 13, color: theme.hintColor),
              ),

              const SizedBox(height: Space.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(
                  'The recruiter has asked you to take this test as part of '
                  'your application. You get one attempt, and the timer '
                  'starts the moment you begin — open it when you have '
                  '$minutes uninterrupted minutes.',
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
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
  final Map<String, dynamic>? test;

  const _ApplicationCard({required this.app, this.test});

  bool get _hasTest => test != null;
  bool get _testDone => test?['status'] == 'submitted';

  /// Where this application sits on the pipeline. An assessment only
  /// becomes a stage once one has actually been sent, so the track stays
  /// honest for applications that never had one.
  int _stage(String status) {
    if (status == 'rejected') return -1;
    if (status == 'selected') return _hasTest ? 4 : 3;
    if (status == 'interview') return _hasTest ? 3 : 2;
    if (status == 'shortlisted') return _hasTest && _testDone ? 2 : 1;
    return 0;
  }

  List<String> get _labels => _hasTest
      ? const ['Applied', 'Shortlisted', 'Assessment', 'Interview', 'Result']
      : const ['Applied', 'Shortlisted', 'Interview', 'Result'];

  String _message(String status) {
    if (status == 'shortlisted' && _hasTest) {
      return _testDone
          ? 'Assessment submitted. The recruiter is reviewing your result.'
          : 'Your profile was shortlisted. Take the assessment above to '
                'move forward.';
    }

    return switch (status) {
      'shortlisted' =>
        'Your profile was shortlisted. The team will be in touch.',
      'on_hold' => 'Your application is under consideration.',
      'interview' => 'You have moved to the interview stage.',
      'selected' => 'Congratulations — you have been selected.',
      'rejected' =>
        'You were not selected for this role. Keep applying — this one '
            'is not a reflection of your abilities.',
      _ => 'Your application has been received.',
    };
  }

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
                _Stepper(stage: stage, color: color, labels: _labels)
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

              if (_testDone) ...[
                const SizedBox(height: Space.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  decoration: BoxDecoration(
                    color: StatusColors.shortlisted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 17,
                        color: StatusColors.shortlisted,
                      ),
                      const SizedBox(width: Space.sm),
                      Text(
                        'Assessment: ${test!['score']}/${test!['total']}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: StatusColors.shortlisted,
                        ),
                      ),
                    ],
                  ),
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
  final List<String> labels;

  const _Stepper({
    required this.stage,
    required this.color,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inactive = theme.dividerColor;

    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
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
              SizedBox(
                width: 62,
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: i <= stage ? color : theme.hintColor,
                    fontWeight: i == stage ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ),
          if (i < labels.length - 1)
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
