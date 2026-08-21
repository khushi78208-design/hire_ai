import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'agent_service.dart';

/// One turn in the conversation. A draft turn carries a proposal the
/// recruiter can act on; everything else is plain text.
class _Turn {
  final bool fromUser;
  final String? text;
  final JobDraft? draft;
  final bool isError;

  _Turn.user(this.text) : fromUser = true, draft = null, isError = false;

  _Turn.assistant(this.text, {this.isError = false})
    : fromUser = false,
      draft = null;

  _Turn.draft(this.draft) : fromUser = false, text = null, isError = false;
}

const _suggestions = [
  'Hire a Java developer with Spring Boot',
  'How many candidates are shortlisted?',
  'Who is the strongest match so far?',
];

class AgentChatSheet extends StatefulWidget {
  /// Called after a draft is created so the vacancies list can refresh.
  final VoidCallback? onJobCreated;

  const AgentChatSheet({super.key, this.onJobCreated});

  static Future<void> show(BuildContext context, {VoidCallback? onJobCreated}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgentChatSheet(onJobCreated: onJobCreated),
    );
  }

  @override
  State<AgentChatSheet> createState() => _AgentChatSheetState();
}

class _AgentChatSheetState extends State<AgentChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Turn> _turns = [];
  bool _sending = false;

  /// The draft currently on screen. While this is set, every message is
  /// treated as an edit to it instead of a new request.
  JobDraft? _activeDraft;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _sending) return;

    setState(() {
      _turns.add(_Turn.user(message));
      _sending = true;
      _controller.clear();
    });
    _scrollToEnd();

    final reply = await AgentService.send(message, currentDraft: _activeDraft);
    if (!mounted) return;

    setState(() {
      _sending = false;

      if (reply.error != null) {
        _turns.add(_Turn.assistant(reply.error, isError: true));
      } else if (reply.clarification != null) {
        _turns.add(_Turn.assistant(reply.clarification));
      } else if (reply.draft != null) {
        _activeDraft = reply.draft;
        _turns.add(_Turn.draft(reply.draft));
        if (reply.draft!.followUp != null) {
          _turns.add(_Turn.assistant(reply.draft!.followUp));
        }
      } else {
        _turns.add(_Turn.assistant(reply.answer));
      }
    });
    _scrollToEnd();
  }

  Future<void> _createDraft(JobDraft draft) async {
    final error = await AgentService.createDraft(draft);
    if (!mounted) return;

    if (error == null) {
      widget.onJobCreated?.call();
      setState(() {
        // The draft is now a real row; further messages start fresh.
        _activeDraft = null;
        _turns.add(
          _Turn.assistant(
            'Saved as a draft. Open it from Vacancies to publish.',
          ),
        );
      });
      _scrollToEnd();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                Space.lg,
                Space.md,
                Space.md,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      'Assistant',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (_activeDraft != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _activeDraft = null;
                        _turns.add(_Turn.assistant('Draft discarded.'));
                      }),
                      child: const Text('Discard draft'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),

            Expanded(
              child: _turns.isEmpty
                  ? _Suggestions(onTap: _send)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(Space.lg),
                      itemCount: _turns.length + (_sending ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _turns.length) return const _Thinking();
                        final turn = _turns[i];

                        if (turn.draft != null) {
                          return _DraftCard(
                            draft: turn.draft!,
                            // Only the newest draft stays actionable — an
                            // older card would create a stale vacancy.
                            isCurrent: turn.draft == _activeDraft,
                            onCreate: () => _createDraft(turn.draft!),
                          );
                        }

                        return _Bubble(turn: turn);
                      },
                    ),
            ),

            Divider(height: 1, color: theme.dividerColor),
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: _activeDraft != null
                            ? 'Ask for a change, or create it'
                            : 'Ask, or describe a role to post',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(_controller.text),
                    icon: const Icon(Icons.arrow_upward, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  final void Function(String) onTap;
  const _Suggestions({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(Space.xl),
      children: [
        const SizedBox(height: Space.xl),
        Icon(
          Icons.auto_awesome,
          size: 40,
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
        const SizedBox(height: Space.md),
        Text(
          'What can I help with?',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: Space.xs),
        Text(
          'I can draft a vacancy or answer questions about your candidates.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: theme.hintColor),
        ),
        const SizedBox(height: Space.xl),
        for (final s in _suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: InkWell(
              onTap: () => onTap(s),
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(s, style: const TextStyle(fontSize: 13.5)),
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Turn turn;
  const _Bubble({required this.turn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: turn.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: Space.md),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: turn.isError
              ? theme.colorScheme.errorContainer
              : turn.fromUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Text(
          turn.text ?? '',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: turn.isError ? theme.colorScheme.onErrorContainer : null,
          ),
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        children: [
          const SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: Space.md),
          Text(
            'Thinking…',
            style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}

class _DraftCard extends StatefulWidget {
  final JobDraft draft;
  final bool isCurrent;
  final VoidCallback onCreate;

  const _DraftCard({
    required this.draft,
    required this.isCurrent,
    required this.onCreate,
  });

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  bool _created = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.draft;
    final active = widget.isCurrent && !_created;

    return Opacity(
      opacity: widget.isCurrent || _created ? 1 : 0.5,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.md),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? theme.colorScheme.primary : theme.dividerColor,
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.sm),

            Wrap(
              spacing: Space.md,
              runSpacing: Space.xs,
              children: [
                _Meta(
                  icon: Icons.place_outlined,
                  text: d.location ?? 'Not set',
                  muted: d.location == null,
                ),
                _Meta(icon: Icons.schedule, text: d.typeLabel),
                _Meta(
                  icon: Icons.work_history_outlined,
                  text: d.experienceLabel,
                ),
                _Meta(
                  icon: Icons.people_outline,
                  text: '${d.openings} opening',
                ),
              ],
            ),

            const SizedBox(height: Space.sm),
            _Meta(
              icon: Icons.payments_outlined,
              text: d.salaryLabel ?? 'Salary not set',
              muted: d.salaryLabel == null,
            ),

            if (d.skills.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: d.skills
                    .map(
                      (s) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(s, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
              ),
            ],

            if (d.description.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              Text(
                d.description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.hintColor,
                ),
              ),
            ],

            const SizedBox(height: Space.lg),

            if (_created)
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: StatusColors.shortlisted,
                  ),
                  const SizedBox(width: Space.sm),
                  const Text(
                    'Created as draft',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              )
            else if (active)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() => _created = true);
                      widget.onCreate();
                    },
                    child: const Text('Create as draft'),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    'Saved unpublished. You review and publish it yourself.',
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
                ],
              )
            else
              Text(
                'Replaced by a newer version',
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool muted;

  const _Meta({required this.icon, required this.text, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = muted
        ? theme.hintColor.withValues(alpha: 0.6)
        : theme.hintColor;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: Space.xs),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontStyle: muted ? FontStyle.italic : null,
          ),
        ),
      ],
    );
  }
}
