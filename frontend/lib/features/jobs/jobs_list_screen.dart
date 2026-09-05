import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/animations.dart';
import 'job_service.dart';
import 'job_detail_screen.dart';

class JobsListScreen extends StatefulWidget {
  final bool isHr;
  const JobsListScreen({super.key, required this.isHr});

  @override
  State<JobsListScreen> createState() => _JobsListScreenState();
}

class _JobsListScreenState extends State<JobsListScreen> {
  final _searchCtrl = TextEditingController();
  List<Job> _jobs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final jobs = await JobService.list(
        search: _searchCtrl.text,
        mine: widget.isHr,
      );
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load jobs. Is the backend running?';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.md,
              Space.lg,
              Space.sm,
            ),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(
                hintText: 'Search job titles',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // Skeletons rather than a spinner: a cold start can take most of a
    // minute, and a blank screen for that long reads as broken.
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.xs,
          Space.lg,
          Space.xl,
        ),
        children: const [SkeletonCard(), SkeletonCard(), SkeletonCard()],
      );
    }

    if (_error != null) {
      return _EmptyState(
        icon: Icons.cloud_off,
        title: 'Something went wrong',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    if (_jobs.isEmpty) {
      return _EmptyState(
        icon: widget.isHr ? Icons.post_add : Icons.work_off_outlined,
        title: widget.isHr ? 'No vacancies yet' : 'No jobs found',
        message: widget.isHr
            ? 'Create your first vacancy to start receiving applications.'
            : 'Try a different search, or check back later.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.xs,
          Space.lg,
          Space.xxl + Space.xl,
        ),
        itemCount: _jobs.length,
        itemBuilder: (context, i) => FadeInItem(
          index: i,
          child: _JobCard(
            job: _jobs[i],
            onTap: () async {
              await Navigator.push(
                context,
                slideRoute(
                  JobDetailScreen(jobId: _jobs[i].id, isHr: widget.isHr),
                ),
              );
              _load();
            },
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;

  const _JobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: PressableCard(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
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
                        job.title,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (job.status != 'open') _StatusChip(status: job.status),
                  ],
                ),
                const SizedBox(height: Space.xs + 2),
                Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 15,
                      color: theme.hintColor,
                    ),
                    const SizedBox(width: Space.xs),
                    Text(
                      job.location ?? 'Remote',
                      style: TextStyle(color: theme.hintColor, fontSize: 13),
                    ),
                    const SizedBox(width: Space.md),
                    Icon(Icons.schedule, size: 15, color: theme.hintColor),
                    const SizedBox(width: Space.xs),
                    Text(
                      job.typeLabel,
                      style: TextStyle(color: theme.hintColor, fontSize: 13),
                    ),
                  ],
                ),
                if (job.skills.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  Wrap(
                    spacing: Space.xs + 2,
                    runSpacing: Space.xs + 2,
                    children: job.skills.take(4).map((s) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: Space.md),
                Row(
                  children: [
                    Text(
                      '₹ ${job.salaryLabel}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${job.experienceMin}+ yrs',
                      style: TextStyle(fontSize: 13, color: theme.hintColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDraft = status == 'draft';
    final color = isDraft ? StatusColors.onHold : StatusColors.applied;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
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
            Container(
              padding: const EdgeInsets.all(Space.xl),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.35,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: Space.lg),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.xs + 2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: Space.xl),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
