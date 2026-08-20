import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Theme.of(context).hintColor),
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
    final onHold = totals['on_hold'] as int;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 600 ? 5 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: Space.md,
            mainAxisSpacing: Space.md,
            childAspectRatio: 1.6,
            children: [
              _Metric(
                label: 'Applications',
                value: totals['applications'],
                onTap: () => widget.onDrillDown?.call(null, null),
              ),
              _Metric(
                label: 'Not reviewed',
                value: totals['applied'],
                color: StatusColors.onHold,
                onTap: () => widget.onDrillDown?.call(null, 'applied'),
              ),
              _Metric(
                label: 'Shortlisted',
                value: totals['shortlisted'],
                color: StatusColors.shortlisted,
                onTap: () => widget.onDrillDown?.call(null, 'shortlisted'),
              ),
              _Metric(
                label: 'Interview',
                value: totals['interview'],
                color: StatusColors.interview,
                onTap: () => widget.onDrillDown?.call(null, 'interview'),
              ),
              _Metric(
                label: 'Selected',
                value: totals['selected'],
                color: StatusColors.selected,
                onTap: () => widget.onDrillDown?.call(null, 'selected'),
              ),
            ],
          ),

          const SizedBox(height: Space.xl),

          // The point of a dashboard is not to show numbers, it is to say
          // what to do next.
          if (unanalysed > 0 || stale > 0 || onHold > 0) ...[
            Text(
              'Needs your attention',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Space.md),
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
                  if (onHold > 0)
                    _AttentionRow(
                      icon: Icons.pause_circle_outline,
                      color: StatusColors.applied,
                      text:
                          '$onHold candidate${onHold == 1 ? "" : "s"} on hold',
                      action: 'View',
                      onTap: () => widget.onDrillDown?.call(null, 'on_hold'),
                      first: unanalysed == 0 && stale == 0,
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.xl),
          ],

          Text('By vacancy', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.md),

          if (jobs.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Center(
                  child: Text(
                    'No vacancies yet',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < jobs.length; i++)
                    _JobRow(
                      job: jobs[i],
                      first: i == 0,
                      onDrillDown: widget.onDrillDown,
                    ),
                ],
              ),
            ),

          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color? color;
  final VoidCallback? onTap;

  const _Metric({
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12.5, color: theme.hintColor),
            ),
            const SizedBox(height: Space.xs),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                height: 1,
                color: color ?? theme.colorScheme.onSurface,
              ),
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

class _JobRow extends StatelessWidget {
  final Map<String, dynamic> job;
  final bool first;
  final void Function(String? jobId, String? status)? onDrillDown;

  const _JobRow({
    required this.job,
    required this.first,
    required this.onDrillDown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = job['id'] as String;

    final chips = <(String, int, Color)>[
      ('new', job['applied'] ?? 0, StatusColors.applied),
      ('shortlisted', job['shortlisted'] ?? 0, StatusColors.shortlisted),
      ('on hold', job['on_hold'] ?? 0, StatusColors.onHold),
      ('interview', job['interview'] ?? 0, StatusColors.interview),
      ('selected', job['selected'] ?? 0, StatusColors.selected),
      ('rejected', job['rejected'] ?? 0, StatusColors.rejected),
    ].where((c) => c.$2 > 0).toList();

    const statusKeys = {
      'new': 'applied',
      'shortlisted': 'shortlisted',
      'on hold': 'on_hold',
      'interview': 'interview',
      'selected': 'selected',
      'rejected': 'rejected',
    };

    return Container(
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job['title'] ?? 'Vacancy',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                '${job['total'] ?? 0} applied',
                style: TextStyle(fontSize: 13, color: theme.hintColor),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: chips
                  .map(
                    (c) => InkWell(
                      onTap: () => onDrillDown?.call(id, statusKeys[c.$1]),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: c.$3.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${c.$2} ${c.$1}',
                          style: TextStyle(fontSize: 12, color: c.$3),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
