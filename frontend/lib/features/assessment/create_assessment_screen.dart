import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'assessment_service.dart';

class CreateAssessmentScreen extends StatefulWidget {
  final String jobId;
  final String jobTitle;

  const CreateAssessmentScreen({
    super.key,
    required this.jobId,
    required this.jobTitle,
  });

  @override
  State<CreateAssessmentScreen> createState() => _CreateAssessmentScreenState();
}

class _CreateAssessmentScreenState extends State<CreateAssessmentScreen> {
  late final TextEditingController _titleCtrl;
  final _durationCtrl = TextEditingController(text: '20');

  List<Question> _questions = [];
  int _count = 10;
  bool _generating = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: '${widget.jobTitle} assessment');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });

    final (questions, error) = await AssessmentService.generate(
      jobId: widget.jobId,
      count: _count,
    );

    if (!mounted) return;
    setState(() {
      _generating = false;
      if (questions != null) _questions = questions;
      _error = error;
    });
  }

  Future<void> _send() async {
    if (_questions.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send this assessment?'),
        content: Text(
          '${_questions.length} questions will go to every shortlisted '
          'candidate for this vacancy. You cannot edit it after sending.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    final (sentTo, error) = await AssessmentService.send(
      jobId: widget.jobId,
      title: _titleCtrl.text.trim(),
      durationMin: int.tryParse(_durationCtrl.text) ?? 20,
      questions: _questions,
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (error == null) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sent to $sentTo candidates')));
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('New assessment')),
      body: ListView(
        padding: const EdgeInsets.all(Space.lg),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: Space.md),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (minutes)',
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _count,
                  decoration: const InputDecoration(labelText: 'Questions'),
                  items: const [5, 10, 15, 20]
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                      .toList(),
                  onChanged: (v) => setState(() => _count = v ?? 10),
                ),
              ),
            ],
          ),

          const SizedBox(height: Space.lg),

          if (_questions.isEmpty)
            _GenerateCard(generating: _generating, onGenerate: _generate)
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_questions.length} questions',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Regenerate'),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              'Tap an option to change the correct answer. Review before '
              'sending — candidates see these exactly as written.',
              style: TextStyle(fontSize: 12.5, color: theme.hintColor),
            ),
            const SizedBox(height: Space.md),

            for (var i = 0; i < _questions.length; i++)
              _QuestionCard(
                index: i + 1,
                question: _questions[i],
                onCorrectChanged: (v) =>
                    setState(() => _questions[i].correct = v),
                onDelete: () => setState(() => _questions.removeAt(i)),
              ),
          ],

          if (_error != null) ...[
            const SizedBox(height: Space.lg),
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 20,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: Space.xxl),
        ],
      ),
      bottomNavigationBar: _questions.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      _sending ? 'Sending…' : 'Send to shortlisted candidates',
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _GenerateCard extends StatelessWidget {
  final bool generating;
  final VoidCallback onGenerate;

  const _GenerateCard({required this.generating, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          children: [
            Icon(
              Icons.auto_awesome,
              size: 36,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: Space.md),
            Text('Generate questions', style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.xs),
            Text(
              'Questions are written from this vacancy\'s skills and '
              'experience level. You review everything before it goes out.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: theme.hintColor),
            ),
            const SizedBox(height: Space.lg),
            if (generating)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: Space.md),
                  Text(
                    'Writing questions…',
                    style: TextStyle(fontSize: 13, color: theme.hintColor),
                  ),
                ],
              )
            else
              FilledButton(
                onPressed: onGenerate,
                child: const Text('Generate'),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final int index;
  final Question question;
  final void Function(int) onCorrectChanged;
  final VoidCallback onDelete;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.onCorrectChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$index.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      question.text,
                      style: const TextStyle(fontSize: 14.5, height: 1.4),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remove',
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),

              for (var i = 0; i < question.options.length; i++)
                InkWell(
                  onTap: () => onCorrectChanged(i),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
                    child: Row(
                      children: [
                        Icon(
                          i == question.correct
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 19,
                          color: i == question.correct
                              ? StatusColors.shortlisted
                              : theme.dividerColor,
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            question.options[i],
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: i == question.correct
                                  ? FontWeight.w600
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (question.explanation.isNotEmpty) ...[
                const SizedBox(height: Space.sm),
                Text(
                  question.explanation,
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
