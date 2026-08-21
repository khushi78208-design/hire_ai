import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';

/// A job the assistant proposed. It exists only in memory until the
/// recruiter presses the button — nothing is saved on the server.
class JobDraft {
  final String title;
  final String description;
  final List<String> skills;
  final String? location;
  final String employmentType;
  final int experienceMin;
  final int? experienceMax;
  final int? salaryMin;
  final int? salaryMax;
  final int openings;
  final List<String> missingFields;
  final String? followUp;

  /// The exact payload the model returned, sent back untouched when the
  /// recruiter asks for a change so nothing is lost in the round trip.
  final Map<String, dynamic> raw;

  JobDraft({
    required this.title,
    required this.description,
    required this.skills,
    this.location,
    required this.employmentType,
    required this.experienceMin,
    this.experienceMax,
    this.salaryMin,
    this.salaryMax,
    required this.openings,
    required this.missingFields,
    this.followUp,
    required this.raw,
  });

  factory JobDraft.fromJson(Map<String, dynamic> j) => JobDraft(
    title: j['title'] ?? '',
    description: j['description'] ?? '',
    skills: (j['skills'] as List?)?.map((e) => e.toString()).toList() ?? [],
    location: j['location'],
    employmentType: j['employment_type'] ?? 'full_time',
    experienceMin: j['experience_min'] ?? 0,
    experienceMax: j['experience_max'],
    salaryMin: j['salary_min'],
    salaryMax: j['salary_max'],
    openings: j['openings'] ?? 1,
    missingFields:
        (j['missing_fields'] as List?)?.map((e) => e.toString()).toList() ?? [],
    followUp: j['follow_up'],
    raw: j,
  );

  Map<String, dynamic> toPayload() => {
    'title': title,
    'description': description,
    'skills': skills,
    if (location != null) 'location': location,
    'employment_type': employmentType,
    'experience_min': experienceMin,
    if (experienceMax != null) 'experience_max': experienceMax,
    if (salaryMin != null) 'salary_min': salaryMin,
    if (salaryMax != null) 'salary_max': salaryMax,
    'openings': openings,
    // Always a draft. The assistant never publishes.
    'status': 'draft',
  };

  String get typeLabel => employmentType
      .replaceAll('_', ' ')
      .replaceFirstMapped(RegExp(r'^\w'), (m) => m.group(0)!.toUpperCase());

  String get experienceLabel {
    if (experienceMax != null) return '$experienceMin–$experienceMax yrs';
    return '$experienceMin+ yrs';
  }

  String? get salaryLabel {
    if (salaryMin == null && salaryMax == null) return null;
    String f(int v) => '${(v / 100000).toStringAsFixed(1)}L';
    if (salaryMax == null) return '₹ ${f(salaryMin!)}+';
    if (salaryMin == null) return '₹ up to ${f(salaryMax!)}';
    return '₹ ${f(salaryMin!)} – ${f(salaryMax!)}';
  }
}

class AgentReply {
  final String? answer;
  final JobDraft? draft;
  final String? clarification;
  final String? error;

  AgentReply({this.answer, this.draft, this.clarification, this.error});
}

class AgentService {
  static final Dio _dio = ApiClient().dio;

  /// Pass [currentDraft] when a draft is already on screen — the message is
  /// then treated as an edit to it rather than a brand new request.
  static Future<AgentReply> send(
    String message, {
    JobDraft? currentDraft,
  }) async {
    try {
      final res = await _dio.post(
        '/agent/chat',
        data: {
          'message': message,
          if (currentDraft != null) 'draft': currentDraft.raw,
        },
      );

      if (res.data?['success'] != true) {
        final msg = res.data?['error']?['message'];
        return AgentReply(
          error: msg is String ? msg : 'The assistant could not respond',
        );
      }

      final data = res.data['data'] as Map<String, dynamic>;

      if (data['type'] == 'draft') {
        final draft = data['draft'] as Map<String, dynamic>;

        // The model asks a question instead of guessing when the request
        // names no role at all.
        final clarify = draft['needs_clarification'];
        if (clarify is String && clarify.isNotEmpty) {
          return AgentReply(clarification: clarify);
        }

        return AgentReply(draft: JobDraft.fromJson(draft));
      }

      return AgentReply(answer: data['answer'] as String? ?? '');
    } on DioException {
      return AgentReply(error: 'Could not reach the assistant');
    }
  }

  /// Creates the job the assistant proposed, as a draft the recruiter
  /// still has to publish themselves.
  static Future<String?> createDraft(JobDraft draft) async {
    try {
      final res = await _dio.post('/jobs', data: draft.toPayload());
      if (res.data?['success'] == true) return null;

      final err = res.data?['error'];
      final details = err?['details'];
      if (details is List && details.isNotEmpty) {
        return details.map((d) => d['message']).join('\n');
      }
      return err?['message'] ?? 'Could not create the vacancy';
    } on DioException {
      return 'Network error. Try again.';
    }
  }
}
