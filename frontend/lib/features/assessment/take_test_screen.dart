import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'assessment_service.dart';

class TakeTestScreen extends StatefulWidget {
  final String attemptId;

  const TakeTestScreen({super.key, required this.attemptId});

  @override
  State<TakeTestScreen> createState() => _TakeTestScreenState();
}

class _TakeTestScreenState extends State<TakeTestScreen>
    with WidgetsBindingObserver {
  ActiveTest? _test;
  bool _loading = true;
  bool _started = false;
  bool _submitting = false;
  String? _error;

  final Map<String, int> _answers = {};
  int _current = 0;
  int _tabSwitches = 0;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Recorded, not punished. The recruiter sees the count and decides
    // what it's worth.
    if (_started && state == AppLifecycleState.paused) {
      setState(() => _tabSwitches++);
    }
  }

  Future<void> _load() async {
    final (test, error) = await AssessmentService.start(widget.attemptId);
    if (!mounted) return;

    setState(() {
      _test = test;
      _error = error;
      _loading = false;
      if (test != null) _remaining = test.remaining;
    });
  }

  void _beginTest() {
    setState(() => _started = true);

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _test?.remaining ?? Duration.zero;

      if (left <= Duration.zero) {
        _ticker?.cancel();
        // Time is up — submit whatever is answered rather than losing it.
        _submit(auto: true);
      } else if (mounted) {
        setState(() => _remaining = left);
      }
    });
  }

  Future<void> _submit({bool auto = false}) async {
    if (_submitting) return;

    if (!auto) {
      final unanswered = (_test?.questions.length ?? 0) - _answers.length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Submit your test?'),
          content: Text(
            unanswered > 0
                ? '$unanswered question${unanswered == 1 ? " is" : "s are"} '
                      'still unanswered. You cannot come back to this.'
                : 'You cannot come back to this once submitted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _submitting = true);
    _ticker?.cancel();

    final (score, total, error) = await AssessmentService.submit(
      attemptId: widget.attemptId,
      answers: _answers,
      tabSwitches: _tabSwitches,
    );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _submitting = false;
        _error = error;
      });
      return;
    }

    // The dialog has to finish before this screen pops — showing it
    // afterwards attaches it to a context that no longer exists, which is
    // why nothing appeared on submit.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.check_circle_outline,
          size: 40,
          color: StatusColors.shortlisted,
        ),
        title: const Text('Test submitted'),
        content: Text(
          auto
              ? 'Time ran out and your answers were submitted automatically. '
                    'You scored $score out of $total. The recruiter will '
                    'review it and be in touch.'
              : 'You scored $score out of $total. The recruiter will review '
                    'it and be in touch.',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String get _clock {
    final m = _remaining.inMinutes.toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final test = _test;
    if (test == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xxl),
            child: Text(
              _error ?? 'Assessment not available',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // Leaving mid-test would strand the attempt with the clock still
    // running, so the back gesture is intercepted.
    return PopScope(
      canPop: !_started,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _started) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Finish and submit the test to leave'),
            ),
          );
        }
      },
      child: _started ? _buildTest(test) : _buildIntro(test),
    );
  }

  Widget _buildIntro(ActiveTest test) {
    final theme = Theme.of(context);
    final expired = test.remaining <= Duration.zero;

    return Scaffold(
      appBar: AppBar(title: const Text('Assessment')),
      body: ListView(
        padding: const EdgeInsets.all(Space.xl),
        children: [
          Text(test.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: Space.xl),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Before you begin', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Space.md),
                  _Rule(
                    icon: Icons.help_outline,
                    text:
                        '${test.questions.length} questions · '
                        '${test.durationMin} minutes',
                  ),
                  _Rule(
                    icon: Icons.timer_outlined,
                    text: 'The timer does not pause once started',
                  ),
                  _Rule(
                    icon: Icons.visibility_outlined,
                    text: 'Leaving the app during the test is recorded',
                  ),
                  _Rule(
                    icon: Icons.gavel_outlined,
                    text: 'Any attempt to cheat disqualifies your application',
                  ),
                  _Rule(
                    icon: Icons.person_outline,
                    text: 'The recruiter reviews every submission',
                  ),
                ],
              ),
            ),
          ),

          if (test.instructions != null && test.instructions!.isNotEmpty) ...[
            const SizedBox(height: Space.lg),
            Text(
              test.instructions!,
              style: const TextStyle(fontSize: 13.5, height: 1.6),
            ),
          ],

          const SizedBox(height: Space.xl),

          if (expired)
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Text(
                'The time for this assessment has passed.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            )
          else
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _beginTest,
                child: const Text('I understand, start test'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTest(ActiveTest test) {
    final theme = Theme.of(context);
    final q = test.questions[_current];
    final selected = _answers[q.id];
    final low = _remaining.inMinutes < 2;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Question ${_current + 1} of ${test.questions.length}'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: Space.lg),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.xs + 2,
            ),
            decoration: BoxDecoration(
              color: (low ? theme.colorScheme.error : theme.colorScheme.primary)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 16,
                  color: low
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: Space.xs + 2),
                Text(
                  _clock,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: low
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: (_current + 1) / test.questions.length,
            minHeight: 3,
            backgroundColor: theme.dividerColor,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.xl),
        children: [
          Text(q.text, style: const TextStyle(fontSize: 17, height: 1.45)),
          const SizedBox(height: Space.xl),

          for (var i = 0; i < q.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: InkWell(
                onTap: () => setState(() => _answers[q.id] = i),
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Container(
                  padding: const EdgeInsets.all(Space.lg),
                  decoration: BoxDecoration(
                    color: selected == i
                        ? theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.4,
                          )
                        : Colors.white,
                    border: Border.all(
                      color: selected == i
                          ? theme.colorScheme.primary
                          : theme.dividerColor,
                      width: selected == i ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected == i
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 21,
                        color: selected == i
                            ? theme.colorScheme.primary
                            : theme.dividerColor,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          q.options[i],
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(
            children: [
              if (_current > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _current--),
                    child: const Text('Previous'),
                  ),
                ),
              if (_current > 0) const SizedBox(width: Space.md),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 50,
                  child: _current == test.questions.length - 1
                      ? FilledButton(
                          onPressed: _submitting ? null : () => _submit(),
                          child: Text(
                            _submitting ? 'Submitting…' : 'Submit test',
                          ),
                        )
                      : FilledButton(
                          onPressed: () => setState(() => _current++),
                          child: const Text('Next'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Rule({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Theme.of(context).hintColor),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
