import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/animations.dart';

class DashboardScreen extends StatefulWidget {
  /// Lets the dashboard hand the recruiter straight to a filtered list.
  final void Function(String? jobId, String? status)? onDrillDown;

  const DashboardScreen({super.key, this.onDrillDown});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Dio _dio = ApiClient().dio;

  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _dio.get('/analysis/dashboard');
      if (!mounted) return;

      if (res.data?['success'] == true) {
        setState(() {
          _data = res.data['data'] as Map<String, dynamic>;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Could not load the dashboard';
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the server';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: const [SkeletonCard(), SkeletonCard()],
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: theme.hintColor),
            const SizedBox(height: Space.lg),
            Text(_error!),
            const SizedBox(height: Space.lg),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final totals = _data!['totals'] as Map<String, dynamic>;
    final jobs = (_data!['jobs'] as List).cast<Map<String, dynamic>>();
    final unanalysed = _data!['unanalysed'] as int;
    final stale = _data!['stale'] as int;

    final openJobs = jobs.where((j) => j['status'] == 'open').length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          Text('Your pipeline', style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            'Tap any number to open that list.',
            style: TextStyle(fontSize: 13, color: theme.hintColor),
          ),
          const SizedBox(height: Space.lg),

          // Four numbers, fixed height. A per-vacancy breakdown here would
          // grow without bound and mostly show zeroes.
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: Space.md,
            mainAxisSpacing: Space.md,
            childAspectRatio: 1.5,
            children: [
              _Metric(
                icon: Icons.work_outline,
                label: 'Open vacancies',
                value: openJobs,
                color: theme.colorScheme.primary,
                onTap: () => widget.onDrillDown?.call(null, null),
              ),
              _Metric(
                icon: Icons.inbox_outlined,
                label: 'Applications',
                value: totals['applications'],
                color: StatusColors.applied,
                onTap: () => widget.onDrillDown?.call(null, 'applied'),
              ),
              _Metric(
                icon: Icons.pending_outlined,
                label: 'Not reviewed',
                value: totals['applied'],
                color: StatusColors.onHold,
                onTap: () => widget.onDrillDown?.call(null, 'applied'),
              ),
              _Metric(
                icon: Icons.check_circle_outline,
                label: 'Shortlisted',
                value: totals['shortlisted'],
                color: StatusColors.shortlisted,
                onTap: () => widget.onDrillDown?.call(null, 'shortlisted'),
              ),
            ],
          ),

          const SizedBox(height: Space.xl),

          // The point of a dashboard is not to show numbers, it is to say
          // what to do next.
          Text('Needs your attention', style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.md),

          if (unanalysed == 0 && stale == 0 && totals['on_hold'] == 0)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 22,
                      color: StatusColors.shortlisted,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        totals['applications'] == 0
                            ? 'No applications yet. They will show up here '
                                  'as they arrive.'
                            : 'Nothing waiting on you right now.',
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  if (unanalysed > 0)
                    _AttentionRow(
                      icon: Icons.auto_awesome,
                      color: StatusColors.onHold,
                      text:
                          '$unanalysed application${unanalysed == 1 ? "" : "s"} '
                          'not analysed yet',
                      action: 'Review',
                      onTap: () => widget.onDrillDown?.call(null, null),
                      first: true,
                    ),
                  if (stale > 0)
                    _AttentionRow(
                      icon: Icons.schedule,
                      color: StatusColors.onHold,
                      text: '$stale shortlisted over 5 days, no decision',
                      action: 'Review',
                      onTap: () =>
                          widget.onDrillDown?.call(null, 'shortlisted'),
                      first: unanalysed == 0,
                    ),
                  if (totals['on_hold'] > 0)
                    _AttentionRow(
                      icon: Icons.pause_circle_outline,
                      color: StatusColors.applied,
                      text:
                          '${totals['on_hold']} candidate${totals['on_hold'] == 1 ? "" : "s"} '
                          'on hold',
                      action: 'View',
                      onTap: () => widget.onDrillDown?.call(null, 'on_hold'),
                      first: unanalysed == 0 && stale == 0,
                    ),
                ],
              ),
            ),

          const SizedBox(height: Space.xl),

          // Later stages matter less day to day, so they sit as a quiet
          // summary rather than four more cards.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _MiniStat(
                    label: 'Interview',
                    value: totals['interview'],
                    color: StatusColors.interview,
                    onTap: () => widget.onDrillDown?.call(null, 'interview'),
                  ),
                  _Divider(),
                  _MiniStat(
                    label: 'Selected',
                    value: totals['selected'],
                    color: StatusColors.selected,
                    onTap: () => widget.onDrillDown?.call(null, 'selected'),
                  ),
                  _Divider(),
                  _MiniStat(
                    label: 'Rejected',
                    value: totals['rejected'],
                    color: StatusColors.rejected,
                    onTap: () => widget.onDrillDown?.call(null, 'rejected'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: Space.xxl),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String label;
  final dynamic value;
  final Color color;
  final VoidCallback? onTap;

  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = value is int ? value as int : 0;

    return PressableCard(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          // A wash of the metric's own colour instead of white on white —
          // four identical cards read as one grey block.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.11),
              color.withValues(alpha: 0.04),
            ],
          ),
          border: Border.all(color: color.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: Colors.white),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Counting up gives the dashboard a moment of life on open.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: count.toDouble()),
                  duration: const Duration(milliseconds: 750),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(
                    '${v.round()}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: -0.5,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
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

class _AttentionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final String action;
  final VoidCallback? onTap;
  final bool first;

  const _AttentionRow({
    required this.icon,
    required this.color,
    required this.text,
    required this.action,
    required this.onTap,
    required this.first,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.sm,
        Space.md,
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: Space.md),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color color;
  final VoidCallback? onTap;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      color: Theme.of(context).dividerColor,
    );
  }
}
