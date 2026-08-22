import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';

/// A question as the recruiter sees it — with the answer key.
class Question {
  final String id;
  final String text;
  final List<String> options;
  int correct;
  final String topic;
  final String explanation;

  Question({
    required this.id,
    required this.text,
    required this.options,
    required this.correct,
    this.topic = '',
    this.explanation = '',
  });

  factory Question.fromJson(Map<String, dynamic> j) => Question(
    id: j['id'] as String,
    text: j['question'] ?? '',
    options: (j['options'] as List?)?.map((e) => e.toString()).toList() ?? [],
    correct: j['correct'] ?? 0,
    topic: j['topic'] ?? '',
    explanation: j['explanation'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': text,
    'options': options,
    'correct': correct,
    if (topic.isNotEmpty) 'topic': topic,
    if (explanation.isNotEmpty) 'explanation': explanation,
  };
}

/// A question as the candidate sees it — no answer key.
class TestQuestion {
  final String id;
  final String text;
  final List<String> options;

  TestQuestion({required this.id, required this.text, required this.options});

  factory TestQuestion.fromJson(Map<String, dynamic> j) => TestQuestion(
    id: j['id'] as String,
    text: j['question'] ?? '',
    options: (j['options'] as List?)?.map((e) => e.toString()).toList() ?? [],
  );
}

class ActiveTest {
  final String attemptId;
  final String title;
  final String? instructions;
  final int durationMin;
  final DateTime startedAt;
  final List<TestQuestion> questions;

  ActiveTest({
    required this.attemptId,
    required this.title,
    this.instructions,
    required this.durationMin,
    required this.startedAt,
    required this.questions,
  });

  /// Time left is derived from the server's start time, not from when this
  /// screen opened — closing and reopening must not reset the clock.
  Duration get remaining {
    final ends = startedAt.add(Duration(minutes: durationMin));
    final left = ends.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

class AssessmentService {
  static final Dio _dio = ApiClient().dio;

  static String? _error(Response res, String fallback) {
    final err = res.data?['error'];
    final details = err?['details'];
    if (details is List && details.isNotEmpty) {
      return details.map((d) => d['message']).join('\n');
    }
    final msg = err?['message'];
    return msg is String ? msg : fallback;
  }

  // ---------------- recruiter ----------------

  static Future<(List<Question>?, String?)> generate({
    required String jobId,
    int count = 10,
  }) async {
    try {
      final res = await _dio.post(
        '/assessments/generate',
        data: {'job_id': jobId, 'count': count},
      );

      if (res.data?['success'] == true) {
        final list = res.data['data']['questions'] as List;
        return (
          list
              .map((q) => Question.fromJson(q as Map<String, dynamic>))
              .toList(),
          null,
        );
      }
      return (null, _error(res, 'Could not generate questions'));
    } on DioException {
      return (null, 'The assistant is taking too long. Try again.');
    }
  }

  static Future<(int?, String?)> send({
    required String jobId,
    required String title,
    required int durationMin,
    required List<Question> questions,
    String? instructions,
  }) async {
    try {
      final res = await _dio.post(
        '/assessments',
        data: {
          'job_id': jobId,
          'title': title,
          'duration_min': durationMin,
          'questions': questions.map((q) => q.toJson()).toList(),
          if (instructions != null && instructions.isNotEmpty)
            'instructions': instructions,
        },
      );

      if (res.data?['success'] == true) {
        return (res.data['data']['sentTo'] as int, null);
      }
      return (null, _error(res, 'Could not send the assessment'));
    } on DioException {
      return (null, 'Network error. Try again.');
    }
  }

  static Future<List<Map<String, dynamic>>> results(String jobId) async {
    try {
      final res = await _dio.get('/assessments/results/$jobId');
      if (res.data?['success'] != true) return [];
      return (res.data['data']['attempts'] as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ---------------- candidate ----------------

  static Future<List<Map<String, dynamic>>> mine() async {
    try {
      final res = await _dio.get('/assessments/mine');
      if (res.data?['success'] != true) return [];
      return (res.data['data']['attempts'] as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<(ActiveTest?, String?)> start(String attemptId) async {
    try {
      final res = await _dio.post('/assessments/attempts/$attemptId/start');

      if (res.data?['success'] == true) {
        final d = res.data['data'];
        return (
          ActiveTest(
            attemptId: d['attemptId'],
            title: d['title'] ?? 'Assessment',
            instructions: d['instructions'],
            durationMin: d['durationMin'] ?? 20,
            startedAt: DateTime.parse(d['startedAt']).toLocal(),
            questions: (d['questions'] as List)
                .map((q) => TestQuestion.fromJson(q as Map<String, dynamic>))
                .toList(),
          ),
          null,
        );
      }
      return (null, _error(res, 'Could not start the assessment'));
    } on DioException {
      return (null, 'Network error. Try again.');
    }
  }

  static Future<(int?, int?, String?)> submit({
    required String attemptId,
    required Map<String, int> answers,
    int tabSwitches = 0,
  }) async {
    try {
      final res = await _dio.post(
        '/assessments/attempts/$attemptId/submit',
        data: {'answers': answers, 'tab_switches': tabSwitches},
      );

      if (res.data?['success'] == true) {
        final d = res.data['data'];
        return (d['score'] as int?, d['total'] as int?, null);
      }
      return (null, null, _error(res, 'Could not submit'));
    } on DioException {
      return (null, null, 'Network error. Your answers were not saved.');
    }
  }
}
