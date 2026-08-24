import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../assessment/assessment_service.dart';
import 'job_service.dart';
import 'evaluation_model.dart';

class ApplicantsScreen extends StatefulWidget {
  /// Set when the recruiter arrives from the dashboard, so the list opens
  /// already narrowed to what they tapped.
  final String? initialJobId;
  final String? initialStatus;

  const ApplicantsScreen({super.key, this.initialJobId, this.initialStatus});

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  final Dio _dio = ApiClient().dio;

  List<Job> _jobs = [];
  Job? _selected;
  List<Map<String, dynamic>> _applicants = [];
  Map<String, Evaluation> _evaluations = {};
  Map<String, Map<String, dynamic>> _testResults = {};
  final Set<String> _analysing = {};
  bool _loadingJobs = true;
  bool _loadingApplicants = false;

  String? _statusFilter;
  int _minScore = 0;

  /// No vacancy selected means "all of them" — the dashboard drills down by
  /// status across every posting, not one at a time.
  bool _allJobs = false;

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatus;
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    final jobs = await JobService.list(mine: true);
    if (!mounted) return;

    Job? initial;
    if (widget.initialJobId != null) {
      // firstWhere would throw if the job was deleted between screens.
      for (final j in jobs) {
        if (j.id == widget.initialJobId) initial = j;
      }
    }

    final showAll = widget.initialJobId == null && widget.initialStatus != null;

    setState(() {
      _jobs = jobs;
      _loadingJobs = false;
      _allJobs = showAll;
      _selected = showAll
          ? null
          : (initial ?? (jobs.isNotEmpty ? jobs.first : null));
    });

    _loadApplicants();
  }

  Future<void> _loadApplicants() async {
    if (!_allJobs && _selected == null) return;

    setState(() => _loadingApplicants = true);

    final path = _allJobs
        ? '/applications/all'
        : '/jobs/${_selected!.id}/applications';

    try {
      final res = await _dio.get(path);
      if (!mounted) return;
      setState(() {
        _applicants = res.data?['success'] == true
            ? (res.data['data']['applications'] as List)
                  .cast<Map<String, dynamic>>()
            : [];
        _loadingApplicants = false;
      });
      _loadEvaluations();
      _loadTestResults();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applicants = [];
        _loadingApplicants = false;
      });
    }
  }

  Future<void> _loadEvaluations() async {
    if (!_allJobs && _selected == null) return;

    final path = _allJobs ? '/analysis/all' : '/analysis/jobs/${_selected!.id}';

    try {
      final res = await _dio.get(path);
      if (res.data?['success'] != true || !mounted) return;

      final list = res.data['data']['evaluations'] as List;
      setState(() {
        _evaluations = {
          for (final e in list)
            (e['application_id'] as String): Evaluation.fromJson(
              e as Map<String, dynamic>,
            ),
        };
      });
    } catch (_) {
      // A missing evaluation is a normal state, not an error worth showing.
    }
  }

  Future<void> _loadTestResults() async {
    final job = _selected;

    // Results are fetched per vacancy, so the all-vacancies view skips them
    // rather than firing one request per job.
    if (job == null) {
      setState(() => _testResults = {});
      return;
    }

    final attempts = await AssessmentService.results(job.id);
    if (!mounted) return;

    setState(() {
      _testResults = {
        for (final a in attempts)
          if (a['application_id'] != null) (a['application_id'] as String): a,
      };
    });
  }

  Future<void> _analyse(String applicationId) async {
    setState(() => _analysing.add(applicationId));

    try {
      final res = await _dio.post('/analysis/applications/$applicationId');

      if (res.data?['success'] == true && mounted) {
        final eval = Evaluation.fromJson(
          res.data['data']['evaluation'] as Map<String, dynamic>,
        );
        setState(() => _evaluations[applicationId] = eval);
      } else if (mounted) {
        final msg = res.data?['error']?['message'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg is String ? msg : 'Analysis failed')),
        );
      }
    } catch (e) {
      if (mounted) {
        // Surface the server's own reason — the usual cause is a missing
        // resume, which the recruiter can actually act on.
        final msg = e is DioException
            ? e.response?.data?['error']?['message']
            : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg is String ? msg : 'Analysis failed. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _analysing.remove(applicationId));
    }
  }

  Future<void> _setStatus(String applicationId, String status) async {
    String? note;

    // A rejection without a reason helps nobody later — but forcing one
    // slows the recruiter down, so it stays optional.
    if (status == 'rejected') {
      note = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: const Text('Reject this candidate?'),
            content: TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason (optional, internal)',
                hintText: 'Looking for more hands-on experience',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Reject'),
              ),
            ],
          );
        },
      );

      if (note == null) return; // cancelled
    }

    try {
      final res = await _dio.patch(
        '/applications/$applicationId/status',
        data: {
          'status': status,
          if (note != null && note.isNotEmpty) 'status_note': note,
        },
      );

      if (res.data?['success'] == true && mounted) {
        setState(() {
          final i = _applicants.indexWhere((a) => a['id'] == applicationId);
          if (i != -1) _applicants[i] = {..._applicants[i], 'status': status};
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked as ${status.replaceAll("_", " ")}')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update status')),
        );
      }
    }
  }

  /// The bucket is private, so a fresh signed URL is minted per view and
  /// handed straight to the browser — the recruiter should never see a raw link.
  Future<void> _openResume(String path) async {
    try {
      final res = await _dio.get(
        '/upload/resume-url',
        queryParameters: {'path': path},
      );

      if (res.data?['success'] != true) throw Exception('no url');

      final url = Uri.parse(res.data['data']['url'] as String);
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);

      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the resume')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open resume')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingJobs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_jobs.isEmpty) {
      return const _Empty(
        icon: Icons.post_add,
        title: 'No vacancies yet',
        message: 'Create a vacancy first — applications will show up here.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.md,
            Space.lg,
            Space.sm,
          ),
          child: DropdownButtonFormField<String>(
            initialValue: _allJobs ? '__all__' : _selected?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Vacancy',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: '__all__',
                child: Text('All vacancies'),
              ),
              ..._jobs.map(
                (j) => DropdownMenuItem(
                  value: j.id,
                  child: Text(j.title, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (id) {
              setState(() {
                _allJobs = id == '__all__';
                _selected = _allJobs
                    ? null
                    : _jobs.firstWhere((j) => j.id == id);
                _evaluations = {};
                _testResults = {};
              });
              _loadApplicants();
            },
          ),
        ),

        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            children: [
              _FilterChip(
                label: 'All',
                selected: _statusFilter == null,
                onTap: () => setState(() => _statusFilter = null),
              ),
              for (final s in const [
                'applied',
                'shortlisted',
                'on_hold',
                'interview',
                'selected',
                'rejected',
              ])
                _FilterChip(
                  label: StatusColors.label(s),
                  color: StatusColors.of(s),
                  selected: _statusFilter == s,
                  onTap: () => setState(
                    () => _statusFilter = _statusFilter == s ? null : s,
                  ),
                ),
              _FilterChip(
                label: 'Score 70+',
                selected: _minScore > 0,
                onTap: () => setState(() => _minScore = _minScore > 0 ? 0 : 70),
              ),
            ],
          ),
        ),

        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_loadingApplicants) {
      return const Center(child: CircularProgressIndicator());
    }

    var list = [..._applicants];

    if (_statusFilter != null) {
      list = list
          .where((a) => (a['status'] ?? 'applied') == _statusFilter)
          .toList();
    }

    if (_minScore > 0) {
      list = list
          .where(
            (a) => (_evaluations[a['id']]?.overallScore ?? -1) >= _minScore,
          )
          .toList();
    }

    if (list.isEmpty) {
      return _Empty(
        icon: Icons.people_outline,
        title: _applicants.isEmpty
            ? 'No applications yet'
            : 'Nothing matches these filters',
        message: _applicants.isEmpty
            ? 'Candidates who apply to this vacancy will appear here.'
            : 'Clear a filter to see more candidates.',
      );
    }

    // Highest score first; unscored applications sink to the bottom so the
    // recruiter always sees the ranked ones without scrolling.
    list.sort((a, b) {
      final sa = _evaluations[a['id']]?.overallScore ?? -1;
      final sb = _evaluations[b['id']]?.overallScore ?? -1;
      return sb.compareTo(sa);
    });

    return RefreshIndicator(
      onRefresh: _loadApplicants,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.xs,
          Space.lg,
          Space.xl,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final app = list[i];
          final id = app['id'] as String;
          return _ApplicantCard(
            app: app,
            evaluation: _evaluations[id],
            testResult: _testResults[id],
            analysing: _analysing.contains(id),
            // Which vacancy an applicant belongs to is only ambiguous when
            // several are on screen at once.
            showJobTitle: _allJobs,
            onOpenResume: _openResume,
            onAnalyse: () => _analyse(id),
            onSetStatus: (status) => _setStatus(id, status),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(right: Space.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md + 2,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: 0.14) : null,
            border: Border.all(color: selected ? c : theme.dividerColor),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? c : theme.colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _ApplicantCard extends StatefulWidget {
  final Map<String, dynamic> app;
  final Evaluation? evaluation;
  final Map<String, dynamic>? testResult;
  final bool analysing;
  final bool showJobTitle;
  final void Function(String path) onOpenResume;
  final VoidCallback onAnalyse;
  final void Function(String status) onSetStatus;

  const _ApplicantCard({
    required this.app,
    required this.evaluation,
    required this.testResult,
    required this.analysing,
    required this.showJobTitle,
    required this.onOpenResume,
    required this.onAnalyse,
    required this.onSetStatus,
  });

  @override
  State<_ApplicantCard> createState() => _ApplicantCardState();
}

class _ApplicantCardState extends State<_ApplicantCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.app;
    final eval = widget.evaluation;

    // Prefer what the candidate typed into the application form over the
    // account name — the form is what they intended for this employer.
    final account = app['users'] as Map<String, dynamic>?;
    final job = app['jobs'] as Map<String, dynamic>?;
    final name = app['full_name'] ?? account?['full_name'] ?? 'Candidate';
    final email = app['email'] ?? account?['email'] ?? '';
    final phone = app['phone'] ?? '';
    final qual = app['qualification'] ?? '';
    final exp = app['experience_years'];
    final city = app['current_city'] ?? '';
    final resumePath = app['resume_path'] as String?;
    final resumeName = app['resume_filename'] ?? 'Resume';
    final note = app['cover_note'] as String?;
    final status = (app['status'] ?? 'applied').toString();
    final initials = name.toString().trim().isEmpty
        ? '?'
        : name.toString().trim()[0].toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showJobTitle && job?['title'] != null) ...[
                Text(
                  job!['title'].toString().toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: Space.sm),
              ],

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.toString(),
                          style: theme.textTheme.titleSmall,
                        ),
                        if (qual.toString().isNotEmpty)
                          Text(
                            '${qual.toString()} · ${exp ?? 0} yrs',
                            style: TextStyle(
                              color: theme.hintColor,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (eval != null) ...[
                        Text(
                          '${eval.overallScore}',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            height: 1,
                            color: ScoreColors.of(eval.overallScore),
                          ),
                        ),
                        Text(
                          eval.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                      if (widget.testResult != null) ...[
                        const SizedBox(height: Space.xs),
                        _TestChip(result: widget.testResult!),
                      ],
                    ],
                  ),
                ],
              ),

              const SizedBox(height: Space.md),
              _StatusBadge(status: status),

              const SizedBox(height: Space.md),
              _Row(icon: Icons.mail_outline, text: email.toString()),
              if (phone.toString().isNotEmpty) ...[
                const SizedBox(height: Space.xs + 2),
                _Row(icon: Icons.phone_outlined, text: phone.toString()),
              ],
              if (city.toString().isNotEmpty) ...[
                const SizedBox(height: Space.xs + 2),
                _Row(icon: Icons.location_city_outlined, text: city.toString()),
              ],

              // The one line that turns a number into a decision the
              // recruiter can actually act on.
              if (eval != null && eval.summary.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Why this score',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.hintColor,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        eval.summary,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],

              if (eval != null && _expanded) ...[
                const SizedBox(height: Space.lg),
                _Bars(eval: eval),
                const SizedBox(height: Space.lg),
                if (eval.matchedSkills.isNotEmpty)
                  _SkillGroup(
                    title: 'Matched',
                    skills: eval.matchedSkills,
                    color: StatusColors.shortlisted,
                  ),
                if (eval.missingSkills.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  _SkillGroup(
                    title: 'Missing',
                    skills: eval.missingSkills,
                    color: theme.colorScheme.error,
                  ),
                ],
                if (eval.strengths.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  _Points(title: 'Strengths', items: eval.strengths),
                ],
                if (eval.concerns.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  _Points(title: 'Concerns', items: eval.concerns),
                ],
                if (eval.locationNote.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  _Row(icon: Icons.place_outlined, text: eval.locationNote),
                ],
                const SizedBox(height: Space.md),
                Text(
                  'AI screening is a recommendation. The hiring decision is yours.',
                  style: TextStyle(fontSize: 11, color: theme.hintColor),
                ),
              ],

              if (note != null && note.isNotEmpty && _expanded) ...[
                const SizedBox(height: Space.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    note,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
              ],

              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (resumePath != null)
                    OutlinedButton.icon(
                      onPressed: () => widget.onOpenResume(resumePath),
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: Text(
                        resumeName.toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (widget.analysing)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: Space.md),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: Space.sm),
                          Text('Analysing…', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: widget.onAnalyse,
                      icon: const Icon(Icons.auto_awesome, size: 17),
                      label: Text(eval == null ? 'Analyse' : 'Re-analyse'),
                    ),
                  if (eval != null)
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? 'Less' : 'Details'),
                    ),
                ],
              ),

              const Divider(),

              // The recruiter decides. Every option stays available at every
              // stage so a decision can always be corrected.
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  _ActionChip(
                    label: 'Shortlist',
                    icon: Icons.check_circle_outline,
                    color: StatusColors.shortlisted,
                    selected: status == 'shortlisted',
                    onTap: () => widget.onSetStatus('shortlisted'),
                  ),
                  _ActionChip(
                    label: 'Hold',
                    icon: Icons.pause_circle_outline,
                    color: StatusColors.onHold,
                    selected: status == 'on_hold',
                    onTap: () => widget.onSetStatus('on_hold'),
                  ),
                  _ActionChip(
                    label: 'Interview',
                    icon: Icons.event_outlined,
                    color: StatusColors.interview,
                    selected: status == 'interview',
                    onTap: () => widget.onSetStatus('interview'),
                  ),
                  _ActionChip(
                    label: 'Select',
                    icon: Icons.star_outline,
                    color: StatusColors.selected,
                    selected: status == 'selected',
                    onTap: () => widget.onSetStatus('selected'),
                  ),
                  _ActionChip(
                    label: 'Reject',
                    icon: Icons.cancel_outlined,
                    color: StatusColors.rejected,
                    selected: status == 'rejected',
                    onTap: () => widget.onSetStatus('rejected'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TestChip extends StatelessWidget {
  final Map<String, dynamic> result;

  const _TestChip({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = result['status'] == 'submitted';

    if (!done) {
      return Text(
        'Test pending',
        style: TextStyle(fontSize: 11, color: theme.hintColor),
      );
    }

    final score = result['score'] as int? ?? 0;
    final total = result['total'] as int? ?? 1;
    final pct = total == 0 ? 0 : (score / total * 100).round();
    final switches = result['tab_switches'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: ScoreColors.of(pct).withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Test $score/$total',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ScoreColors.of(pct),
            ),
          ),
        ),
        // Surfaced only when it happened — a zero here would be noise.
        if (switches > 0) ...[
          const SizedBox(height: 2),
          Text(
            'left app ${switches}x',
            style: TextStyle(fontSize: 10, color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : null,
          border: Border.all(
            color: selected ? color : Theme.of(context).dividerColor,
          ),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? color : null),
            const SizedBox(width: Space.xs + 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? color : null,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = StatusColors.of(status);

    return Container(
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
    );
  }
}

class _Bars extends StatelessWidget {
  final Evaluation eval;
  const _Bars({required this.eval});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      ('Skills', eval.skillScore),
      ('Experience', eval.experienceScore),
      ('Education', eval.educationScore),
      ('Projects', eval.projectScore),
    ];

    return Column(
      children: items.map((e) {
        final color = ScoreColors.of(e.$2);

        return Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Text(
                  e.$1,
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: e.$2 / 100,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              SizedBox(
                width: 28,
                child: Text(
                  '${e.$2}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _SkillGroup extends StatelessWidget {
  final String title;
  final List<String> skills;
  final Color color;

  const _SkillGroup({
    required this.title,
    required this.skills,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).hintColor,
          ),
        ),
        const SizedBox(height: Space.xs + 2),
        Wrap(
          spacing: Space.xs + 2,
          runSpacing: Space.xs + 2,
          children: skills
              .map(
                (s) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(s, style: TextStyle(fontSize: 12, color: color)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _Points extends StatelessWidget {
  final String title;
  final List<String> items;

  const _Points({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).hintColor,
          ),
        ),
        const SizedBox(height: Space.xs),
        ...items.map(
          (t) => Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('· ', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: Text(
                    t,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Row({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Theme.of(context).hintColor),
        const SizedBox(width: Space.xs + 2),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _Empty({
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
