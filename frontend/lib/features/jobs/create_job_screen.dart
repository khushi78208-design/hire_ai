import 'package:flutter/material.dart';
import 'job_service.dart';

class CreateJobScreen extends StatefulWidget {
  /// When non-null the screen edits that job instead of creating a new one.
  final Job? existing;

  const CreateJobScreen({super.key, this.existing});

  @override
  State<CreateJobScreen> createState() => _CreateJobScreenState();
}

class _CreateJobScreenState extends State<CreateJobScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _expCtrl;
  late final TextEditingController _salMinCtrl;
  late final TextEditingController _salMaxCtrl;
  late final TextEditingController _openingsCtrl;
  final _skillCtrl = TextEditingController();

  late List<String> _skills;
  late String _type;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final j = widget.existing;

    _titleCtrl = TextEditingController(text: j?.title ?? '');
    _descCtrl = TextEditingController(text: j?.description ?? '');
    _locationCtrl = TextEditingController(text: j?.location ?? '');
    _expCtrl = TextEditingController(text: '${j?.experienceMin ?? 0}');
    _salMinCtrl = TextEditingController(text: j?.salaryMin?.toString() ?? '');
    _salMaxCtrl = TextEditingController(text: j?.salaryMax?.toString() ?? '');
    _openingsCtrl = TextEditingController(text: '${j?.openings ?? 1}');
    _skills = List<String>.from(j?.skills ?? []);
    _type = j?.employmentType ?? 'full_time';
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _descCtrl,
      _locationCtrl,
      _skillCtrl,
      _expCtrl,
      _salMinCtrl,
      _salMaxCtrl,
      _openingsCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addSkill() {
    final s = _skillCtrl.text.trim();
    if (s.isEmpty || _skills.contains(s)) return;
    setState(() {
      _skills.add(s);
      _skillCtrl.clear();
    });
  }

  Map<String, dynamic> _payload(String status) => {
    'title': _titleCtrl.text.trim(),
    'description': _descCtrl.text.trim(),
    'skills': _skills,
    'location': _locationCtrl.text.trim(),
    'employment_type': _type,
    'experience_min': int.tryParse(_expCtrl.text) ?? 0,
    if (_salMinCtrl.text.isNotEmpty)
      'salary_min': int.tryParse(_salMinCtrl.text),
    if (_salMaxCtrl.text.isNotEmpty)
      'salary_max': int.tryParse(_salMaxCtrl.text),
    'openings': int.tryParse(_openingsCtrl.text) ?? 1,
    'status': status,
  };

  Future<void> _save({required bool publish}) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    // When editing, keep the job's current status unless the user
    // explicitly publishes — silently republishing a closed job would
    // surprise the recruiter.
    final status = _isEditing
        ? (publish ? 'open' : widget.existing!.status)
        : (publish ? 'open' : 'draft');

    final error = _isEditing
        ? await JobService.update(widget.existing!.id, _payload(status))
        : await JobService.create(_payload(status));

    if (!mounted) return;
    setState(() => _saving = false);

    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit vacancy' : 'New vacancy')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Job title',
                hintText: 'Senior Java Developer',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Enter a job title'
                  : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().length < 20)
                  ? 'Describe the role in at least 20 characters'
                  : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'Bengaluru / Remote',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Required skills',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _skillCtrl,
                    onSubmitted: (_) => _addSkill(),
                    decoration: const InputDecoration(
                      hintText: 'Java',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _addSkill,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_skills.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _skills
                    .map(
                      (s) => Chip(
                        label: Text(s),
                        onDeleted: () => setState(() => _skills.remove(s)),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),

            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Employment type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'full_time', child: Text('Full time')),
                DropdownMenuItem(value: 'part_time', child: Text('Part time')),
                DropdownMenuItem(value: 'contract', child: Text('Contract')),
                DropdownMenuItem(
                  value: 'internship',
                  child: Text('Internship'),
                ),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'full_time'),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _expCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Min experience (yrs)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _openingsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Openings',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _salMinCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Salary min (₹)',
                      hintText: '600000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _salMaxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Salary max (₹)',
                      hintText: '900000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : () => _save(publish: !_isEditing),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save changes' : 'Publish vacancy'),
            ),
            if (!_isEditing) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _saving ? null : () => _save(publish: false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Save as draft'),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
