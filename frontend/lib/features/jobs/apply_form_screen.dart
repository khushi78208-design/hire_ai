import 'package:flutter/material.dart';
import 'apply_service.dart';

class ApplyFormScreen extends StatefulWidget {
  final String jobId;
  final String jobTitle;

  const ApplyFormScreen({
    super.key,
    required this.jobId,
    required this.jobTitle,
  });

  @override
  State<ApplyFormScreen> createState() => _ApplyFormScreenState();
}

class _ApplyFormScreenState extends State<ApplyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _qualCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  UploadedResume? _resume;
  bool _uploading = false;
  bool _submitting = false;
  String? _resumeError;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _qualCtrl,
      _expCtrl,
      _noteCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickResume() async {
    setState(() {
      _uploading = true;
      _resumeError = null;
    });

    final (resume, error) = await ApplyService.pickAndUpload();

    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (resume != null) _resume = resume;
      _resumeError = error;
    });
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState!.validate();

    // The file picker is not a FormField, so it needs its own check.
    if (_resume == null) {
      setState(() => _resumeError = 'Upload your resume to continue');
    }

    if (!formOk || _resume == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await ApplyService.submit(
      jobId: widget.jobId,
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      qualification: _qualCtrl.text.trim(),
      experienceYears: int.tryParse(_expCtrl.text.trim()) ?? 0,
      resumePath: _resume!.path,
      resumeFilename: _resume!.filename,
      coverNote: _noteCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Apply')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.jobTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Fill in your details below',
              style: TextStyle(color: theme.hintColor),
            ),
            const SizedBox(height: 24),

            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name *',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Enter your full name'
                  : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email *',
                prefixIcon: Icon(Icons.mail_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter your email';
                if (!v.contains('@') || !v.contains('.')) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile number *',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.length < 10) return 'Enter a valid mobile number';
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _qualCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Highest qualification *',
                hintText: 'B.Tech Computer Science',
                prefixIcon: Icon(Icons.school_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Enter your qualification'
                  : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _expCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Total experience (years) *',
                prefixIcon: Icon(Icons.work_history_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty)
                  return 'Enter your experience';
                if (int.tryParse(v.trim()) == null) return 'Enter a number';
                return null;
              },
            ),
            const SizedBox(height: 24),

            Text('Resume *', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _ResumeBox(
              resume: _resume,
              uploading: _uploading,
              onPick: _pickResume,
              onRemove: () => setState(() => _resume = null),
            ),
            if (_resumeError != null) ...[
              const SizedBox(height: 6),
              Text(
                _resumeError!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),

            TextFormField(
              controller: _noteCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Cover note (optional)',
                hintText: 'Why are you a good fit for this role?',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
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

            const SizedBox(height: 28),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit application'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ResumeBox extends StatelessWidget {
  final UploadedResume? resume;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ResumeBox({
    required this.resume,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (uploading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          children: [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Uploading…'),
          ],
        ),
      );
    }

    if (resume != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          border: Border.all(color: theme.colorScheme.primary),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.description, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                resume!.filename,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Remove',
              onPressed: onRemove,
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(Icons.upload_file, size: 32, color: theme.hintColor),
            const SizedBox(height: 8),
            const Text(
              'Tap to upload resume',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              'PDF or Word, up to 5 MB',
              style: TextStyle(color: theme.hintColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
