import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import 'job_service.dart';

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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applicants = [];
        _loadingApplicants = false;
      });
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
              setState(() => _selected = _jobs.firstWhere((j) => j.id == id));
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

    return RefreshIndicator(
      onRefresh: _loadApplicants,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _applicants.length,
        itemBuilder: (context, i) =>
            _ApplicantCard(app: _applicants[i], onOpenResume: _openResume),
      ),
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  final Map<String, dynamic> app;
  final void Function(String path) onOpenResume;

  const _ApplicantCard({required this.app, required this.onOpenResume});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Prefer what the candidate typed into the application form over the
    // account name — the form is what they intended for this employer.
    final account = app['users'] as Map<String, dynamic>?;
    final name = app['full_name'] ?? account?['full_name'] ?? 'Candidate';
    final email = app['email'] ?? account?['email'] ?? '';
    final phone = app['phone'] ?? '';
    final qual = app['qualification'] ?? '';
    final exp = app['experience_years'];
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
                          qual.toString(),
                          style: TextStyle(
                            color: theme.hintColor,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    '${exp ?? 0} yrs',
                    style: const TextStyle(fontSize: 12),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 14),

            _Row(icon: Icons.mail_outline, text: email.toString()),
            if (phone.toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              _Row(icon: Icons.phone_outlined, text: phone.toString()),
            ],

            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  note,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],

            const SizedBox(height: 14),
            Row(
              children: [
                if (resumePath != null)
                  OutlinedButton.icon(
                    onPressed: () => onOpenResume(resumePath),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(
                      resumeName.toString(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const Spacer(),
                Text(
                  (app['status'] ?? 'applied').toString().toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.hintColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
