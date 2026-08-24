import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../theme/app_theme.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final Dio _dio = ApiClient().dio;

  List<Map<String, dynamic>> _items = [];
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _dio.get('/notifications');
      if (res.data?['success'] != true || !mounted) return;

      setState(() {
        _items = (res.data['data']['notifications'] as List)
            .cast<Map<String, dynamic>>();
        _unread = res.data['data']['unread'] as int? ?? 0;
      });
    } catch (_) {
      // An empty bell is a fine failure mode; an error toast here would
      // interrupt whatever the person is actually doing.
    }
  }

  Future<void> _open() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationSheet(items: _items),
    );

    // Opening the sheet is the read receipt — tracking each item
    // separately is more bookkeeping than it is worth.
    if (_unread > 0) {
      setState(() => _unread = 0);
      try {
        await _dio.post('/notifications/read');
      } catch (_) {}
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none),
          tooltip: 'Notifications',
          onPressed: _open,
        ),
        if (_unread > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 17),
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                _unread > 9 ? '9+' : '$_unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NotificationSheet extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const _NotificationSheet({required this.items});

  String _ago(String? iso) {
    if (iso == null) return '';
    final then = DateTime.tryParse(iso)?.toLocal();
    if (then == null) return '';

    final d = DateTime.now().difference(then);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${then.day}/${then.month}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
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
                Expanded(
                  child: Text(
                    'Notifications',
                    style: theme.textTheme.titleMedium,
                  ),
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
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.xxl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 44,
                            color: theme.hintColor,
                          ),
                          const SizedBox(height: Space.md),
                          Text(
                            'Nothing yet',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            'New vacancies and applications will show up here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: theme.dividerColor),
                    itemBuilder: (context, i) {
                      final n = items[i];
                      final unread = n['read_at'] == null;
                      final isVacancy = n['type'] == 'new_vacancy';

                      return Container(
                        color: unread
                            ? theme.colorScheme.primaryContainer.withValues(
                                alpha: 0.18,
                              )
                            : null,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.xl,
                          vertical: Space.md,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(Space.sm),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                isVacancy
                                    ? Icons.work_outline
                                    : Icons.person_add_alt,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n['title'] ?? '',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: unread
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  if (n['body'] != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      n['body'],
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: theme.hintColor,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            Text(
                              _ago(n['created_at']),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
