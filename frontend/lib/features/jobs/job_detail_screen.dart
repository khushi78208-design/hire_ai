import 'package:flutter/material.dart';
import 'job_service.dart';
import 'create_job_screen.dart';
import 'apply_form_screen.dart';

class JobDetailScreen extends StatefulWidget {
  final String jobId;
  final bool isHr;

  const JobDetailScreen({super.key, required this.jobId, required this.isHr});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  Job? _job;
  bool _hasApplied = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (job, applied) = await JobService.detail(widget.jobId);
    if (!mounted) return;
    setState(() {
      _job = job;
      _hasApplied = applied;
      _loading = false;
    });
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _apply() async {
    final job = _job;
    if (job == null) return;

    final applied = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ApplyFormScreen(jobId: job.id, jobTitle: job.title),
      ),
    );

    if (!mounted) return;
    if (applied == true) {
      setState(() => _hasApplied = true);
      _toast('Application submitted');
    }
  }

  Future<void> _changeStatus(String status, String successMsg) async {
    setState(() => _busy = true);
    final error = await JobService.setStatus(widget.jobId, status);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      await _load();
      if (mounted) _toast(successMsg);
    } else {
      _toast(error, error: true);
    }
  }

  Future<void> _edit() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CreateJobScreen(existing: _job)),
    );
    if (updated == true) _load();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this vacancy?'),
        content: const Text(
          'This also removes every application submitted to it. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final error = await JobService.delete(widget.jobId);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
      _toast('Vacancy deleted');
    } else {
      _toast(error, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final job = _job;
    if (job == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Job not found')),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job details'),
        actions: [
          if (widget.isHr)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _edit();
                  case 'publish':
                    _changeStatus('open', 'Vacancy published');
                  case 'close':
                    _changeStatus('closed', 'Vacancy closed');
                  case 'reopen':
                    _changeStatus('open', 'Vacancy reopened');
                  case 'draft':
                    _changeStatus('draft', 'Moved back to draft');
                  case 'delete':
                    _confirmDelete();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (job.isDraft)
                  const PopupMenuItem(
                    value: 'publish',
                    child: ListTile(
                      leading: Icon(Icons.publish_outlined),
                      title: Text('Publish'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (job.isOpen) ...[
                  const PopupMenuItem(
                    value: 'draft',
                    child: ListTile(
                      leading: Icon(Icons.unpublished_outlined),
                      title: Text('Unpublish'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'close',
                    child: ListTile(
                      leading: Icon(Icons.lock_outline),
                      title: Text('Close vacancy'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                if (job.isClosed)
                  const PopupMenuItem(
                    value: 'reopen',
                    child: ListTile(
                      leading: Icon(Icons.lock_open_outlined),
                      title: Text('Reopen'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.isHr) _StatusBadge(job: job),
            ],
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _MetaItem(
                icon: Icons.place_outlined,
                text: job.location ?? 'Remote',
              ),
              _MetaItem(icon: Icons.schedule, text: job.typeLabel),
              _MetaItem(
                icon: Icons.work_history_outlined,
                text: '${job.experienceMin}+ yrs',
              ),
              _MetaItem(
                icon: Icons.people_outline,
                text: '${job.openings} opening${job.openings > 1 ? "s" : ""}',
              ),
            ],
          ),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined, size: 20),
                const SizedBox(width: 10),
                Text(
                  '₹ ${job.salaryLabel} per year',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          if (job.skills.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Required skills', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: job.skills
                  .map(
                    (s) => Chip(
                      label: Text(s),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],

          const SizedBox(height: 24),
          Text('About this role', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(job.description, style: const TextStyle(height: 1.6)),
        ],
      ),
      bottomNavigationBar: _buildAction(job),
    );
  }

  Widget? _buildAction(Job job) {
    if (widget.isHr) {
      if (job.isDraft) {
        return _BottomBar(
          child: FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _changeStatus('open', 'Vacancy published'),
            icon: const Icon(Icons.publish_outlined),
            label: const Text('Publish vacancy'),
          ),
        );
      }
      return null;
    }

    if (_hasApplied) {
      return _BottomBar(
        child: FilledButton.tonalIcon(
          onPressed: null,
          icon: const Icon(Icons.check),
          label: const Text('Applied'),
        ),
      );
    }

    return _BottomBar(
      child: FilledButton(
        onPressed: _busy ? null : _apply,
        child: _busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Apply now'),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Job job;
  const _StatusBadge({required this.job});

  @override
  Widget build(BuildContext context) {
    final color = job.isOpen
        ? Colors.green
        : job.isDraft
        ? Colors.orange
        : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        job.statusLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color.shade800,
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final Widget child;
  const _BottomBar({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(height: 52, width: double.infinity, child: child),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).hintColor),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: Theme.of(context).hintColor)),
      ],
    );
  }
}
