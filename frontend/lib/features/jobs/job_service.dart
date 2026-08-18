import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';

class Job {
  final String id;
  final String title;
  final String description;
  final String? requirements;
  final String? location;
  final List<String> skills;
  final String employmentType;
  final int experienceMin;
  final int? salaryMin;
  final int? salaryMax;
  final int openings;
  final String status;

  Job({
    required this.id,
    required this.title,
    required this.description,
    this.requirements,
    this.location,
    required this.skills,
    required this.employmentType,
    required this.experienceMin,
    this.salaryMin,
    this.salaryMax,
    required this.openings,
    required this.status,
  });

  factory Job.fromJson(Map<String, dynamic> j) => Job(
    id: j['id'] as String,
    title: j['title'] ?? '',
    description: j['description'] ?? '',
    requirements: j['requirements'],
    location: j['location'],
    skills: (j['skills'] as List?)?.map((e) => e.toString()).toList() ?? [],
    employmentType: j['employment_type'] ?? 'full_time',
    experienceMin: j['experience_min'] ?? 0,
    salaryMin: j['salary_min'],
    salaryMax: j['salary_max'],
    openings: j['openings'] ?? 1,
    status: j['status'] ?? 'draft',
  );

  String get salaryLabel {
    if (salaryMin == null && salaryMax == null) return 'Not disclosed';
    String f(int v) => '${(v / 100000).toStringAsFixed(1)}L';
    if (salaryMax == null) return '${f(salaryMin!)}+';
    return '${f(salaryMin ?? 0)} – ${f(salaryMax!)}';
  }

  String get typeLabel => employmentType
      .replaceAll('_', ' ')
      .replaceFirstMapped(RegExp(r'^\w'), (m) => m.group(0)!.toUpperCase());

  bool get isDraft => status == 'draft';
  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';

  String get statusLabel {
    switch (status) {
      case 'draft':
        return 'Draft';
      case 'open':
        return 'Open';
      case 'closed':
        return 'Closed';
      default:
        return status;
    }
  }
}

class JobService {
  static final Dio _dio = ApiClient().dio;

  static Future<List<Job>> list({String? search, bool mine = false}) async {
    final res = await _dio.get(
      '/jobs',
      queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (mine) 'mine': 'true',
      },
    );

    if (res.data?['success'] != true) return [];
    final list = res.data['data']['jobs'] as List;
    return list.map((j) => Job.fromJson(j)).toList();
  }

  static Future<(Job?, bool)> detail(String id) async {
    final res = await _dio.get('/jobs/$id');
    if (res.data?['success'] != true) return (null, false);
    return (
      Job.fromJson(res.data['data']['job']),
      res.data['data']['hasApplied'] == true,
    );
  }

  static Future<String?> create(Map<String, dynamic> body) async {
    final res = await _dio.post('/jobs', data: body);
    if (res.data?['success'] == true) return null;
    return res.data?['error']?['message'] ?? 'Could not create job';
  }

  static Future<String?> update(String id, Map<String, dynamic> body) async {
    final res = await _dio.patch('/jobs/$id', data: body);
    if (res.data?['success'] == true) return null;
    return res.data?['error']?['message'] ?? 'Could not update job';
  }

  static Future<String?> setStatus(String id, String status) async {
    final res = await _dio.patch('/jobs/$id', data: {'status': status});
    if (res.data?['success'] == true) return null;
    return res.data?['error']?['message'] ?? 'Could not update status';
  }

  static Future<String?> delete(String id) async {
    final res = await _dio.delete('/jobs/$id');
    if (res.data?['success'] == true) return null;
    return res.data?['error']?['message'] ?? 'Could not delete job';
  }

  static Future<String?> apply(String id) async {
    final res = await _dio.post('/jobs/$id/apply');
    if (res.data?['success'] == true) return null;
    return res.data?['error']?['message'] ?? 'Could not apply';
  }

  static Future<List<Map<String, dynamic>>> myApplications() async {
    final res = await _dio.get('/applications/me');
    if (res.data?['success'] != true) return [];
    return (res.data['data']['applications'] as List)
        .cast<Map<String, dynamic>>();
  }
}
