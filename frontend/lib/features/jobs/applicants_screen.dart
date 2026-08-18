import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import 'job_service.dart';
import 'evaluation_model.dart';

class ApplicantsScreen extends StatefulWidget {
  const ApplicantsScreen({super.key});

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  final Dio _dio = ApiClient().dio;

  List<Job> _jobs = [];
  Job? _selected;
  List<Map<String, dynamic>> _applicants = [];
  Map<String, Evaluation> _evaluations = {};
  final Set<String> _analysing = {};
  bool _loadingJobs = true;
  bool _loadingApplicants = false;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    final jobs = await JobService.list(mine: true);
    if (!mounted) return;
    setState(() {
      _jobs = jobs;
      _loadingJobs = false;
      if (jobs.isNotEmpty) _selected = jobs.first;
    });
    if (_selected != null) _loadApplicants();
  }

  Future<void> _loadApplicants() async {
    final job = _selected;
    if (job == null) return;

    setState(() => _loadingApplicants = true);

    try {
      final res = await _dio.get('/jobs/${job.id}/applications');
      if (!mounted) return;
      setState(() {
        _applicants = res.data?['success'] == true
            ? (res.data['data']['applications'] as List)
                  .cast<Map<String, dynamic>>()
            : [];
        _loadingApplicants = false;
      });
      _loadEvaluations();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applicants = [];
        _loadingApplicants = false;
      });
    }
  }

  Future<void> _loadEvaluations() async {
    final job = _selected;
    if (job == null) return;

    try {
      final res = await _dio.get('/analysis/jobs/${job.id}');
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Analysis failed. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _analysing.remove(applicationId));
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: DropdownButtonFormField<String>(
            initialValue: _selected?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Vacancy',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _jobs
                .map(
                  (j) => DropdownMenuItem(
                    value: j.id,
                    child: Text(j.title, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (id) {
              setState(() {
                _selected = _jobs.firstWhere((j) => j.id == id);
                _evaluations = {};
              });
              _loadApplicants();
            },
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

    if (_applicants.isEmpty) {
      return const _Empty(
        icon: Icons.people_outline,
        title: 'No applications yet',
        message: 'Candidates who apply to this vacancy will appear here.',
      );
    }

    // Highest score first; unscored applications sink to the bottom so the
    // recruiter always sees the ranked ones without scrolling.
    final sorted = [..._applicants];
    sorted.sort((a, b) {
      final sa = _evaluations[a['id']]?.overallScore ?? -1;
      final sb = _evaluations[b['id']]?.overallScore ?? -1;
      return sb.compareTo(sa);
    });

    return RefreshIndicator(
      onRefresh: _loadApplicants,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: sorted.length,
        itemBuilder: (context, i) {
          final app = sorted[i];
          final id = app['id'] as String;
          return _ApplicantCard(
            app: app,
            evaluation: _evaluations[id],
            analysing: _analysing.contains(id),
            onOpenResume: _openResume,
            onAnalyse: () => _analyse(id),
          );
        },
      ),
    );
  }
}

class _ApplicantCard extends StatefulWidget {
  final Map<String, dynamic> app;
  final Evaluation? evaluation;
  final bool analysing;
  final void Function(String path) onOpenResume;
  final VoidCallback onAnalyse;

  const _ApplicantCard({
    required this.app,
    required this.evaluation,
    required this.analysing,
    required this.onOpenResume,
    required this.onAnalyse,
  });

  @override
  State<_ApplicantCard> createState() => _ApplicantCardState();
}

class _ApplicantCardState extends State<_ApplicantCard> {
  bool _expanded = false;

  Color _scoreColor(int score, ThemeData theme) {
    if (score >= 80) return Colors.green.shade700;
    if (score >= 50) return Colors.orange.shade800;
    return theme.colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = widget.app;
    final eval = widget.evaluation;

    // Prefer what the candidate typed into the application form over the
    // account name — the form is what they intended for this employer.
    final account = app['users'] as Map<String, dynamic>?;
    final name = app['full_name'] ?? account?['full_name'] ?? 'Candidate';
    final email = app['email'] ?? account?['email'] ?? '';
    final phone = app['phone'] ?? '';
    final qual = app['qualification'] ?? '';
    final exp = app['experience_years'];
    final city = app['current_city'] ?? '';
    final resumePath = app['resume_path'] as String?;
    final resumeName = app['resume_filename'] ?? 'Resume';
    final note = app['cover_note'] as String?;
    final initials = name.toString().trim().isEmpty
        ? '?'
        : name.toString().trim()[0].toUpperCase();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
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
                if (eval != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${eval.overallScore}',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          color: _scoreColor(eval.overallScore, theme),
                        ),
                      ),
                      Text(
                        eval.label,
                        style: TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 14),
            _Row(icon: Icons.mail_outline, text: email.toString()),
            if (phone.toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              _Row(icon: Icons.phone_outlined, text: phone.toString()),
            ],
            if (city.toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              _Row(icon: Icons.location_city_outlined, text: city.toString()),
            ],

            // The one line that turns a number into a decision the recruiter
            // can actually act on.
            if (eval != null && eval.summary.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
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
                    const SizedBox(height: 4),
                    Text(
                      eval.summary,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],

            if (eval != null && _expanded) ...[
              const SizedBox(height: 16),
              _Bars(eval: eval),
              const SizedBox(height: 16),
              if (eval.matchedSkills.isNotEmpty)
                _SkillGroup(
                  title: 'Matched',
                  skills: eval.matchedSkills,
                  color: Colors.green.shade700,
                ),
              if (eval.missingSkills.isNotEmpty) ...[
                const SizedBox(height: 10),
                _SkillGroup(
                  title: 'Missing',
                  skills: eval.missingSkills,
                  color: theme.colorScheme.error,
                ),
              ],
              if (eval.strengths.isNotEmpty) ...[
                const SizedBox(height: 14),
                _Points(title: 'Strengths', items: eval.strengths),
              ],
              if (eval.concerns.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Points(title: 'Concerns', items: eval.concerns),
              ],
              if (eval.locationNote.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Row(icon: Icons.place_outlined, text: eval.locationNote),
              ],
              const SizedBox(height: 12),
              Text(
                'AI screening is a recommendation. The hiring decision is yours.',
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
            ],

            if (note != null && note.isNotEmpty && _expanded) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  note,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],

            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
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
          ],
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
        final color = e.$2 >= 70
            ? Colors.green.shade700
            : e.$2 >= 45
            ? Colors.orange.shade800
            : theme.colorScheme.error;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
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
              const SizedBox(width: 8),
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
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
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
        const SizedBox(height: 4),
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
        const SizedBox(width: 6),
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
