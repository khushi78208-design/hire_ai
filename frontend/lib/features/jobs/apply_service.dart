import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api/api_client.dart';

class UploadedResume {
  final String path;
  final String filename;
  UploadedResume(this.path, this.filename);
}

class ApplyService {
  static final Dio _dio = ApiClient().dio;

  /// Returns (resume, errorMessage). Exactly one is non-null.
  static Future<(UploadedResume?, String?)> pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
      withData: true, // needed on web — path is null there
    );

    if (result == null || result.files.isEmpty) return (null, null);

    final file = result.files.single;
    final bytes = file.bytes;

    if (bytes == null) return (null, 'Could not read that file');
    if (bytes.length > 5 * 1024 * 1024) {
      return (null, 'Resume must be under 5 MB');
    }

    try {
      final form = FormData.fromMap({
        'resume': MultipartFile.fromBytes(bytes, filename: file.name),
      });

      final res = await _dio.post('/upload/resume', data: form);

      if (res.data?['success'] == true) {
        final d = res.data['data'];
        return (UploadedResume(d['path'], d['filename']), null);
      }

      final msg = res.data?['error']?['message'];
      return (null, msg is String ? msg : 'Upload failed');
    } on DioException {
      return (null, 'Upload failed. Check your connection.');
    }
  }

  static Future<String?> submit({
    required String jobId,
    required String fullName,
    required String email,
    required String phone,
    required String qualification,
    required int experienceYears,
    required String currentCity,
    required bool willingToRelocate,
    required String resumePath,
    required String resumeFilename,
    String? coverNote,
  }) async {
    try {
      final res = await _dio.post(
        '/jobs/$jobId/apply',
        data: {
          'full_name': fullName,
          'email': email,
          'phone': phone,
          'qualification': qualification,
          'experience_years': experienceYears,
          'current_city': currentCity,
          'willing_to_relocate': willingToRelocate,
          'resume_path': resumePath,
          'resume_filename': resumeFilename,
          if (coverNote != null && coverNote.isNotEmpty)
            'cover_note': coverNote,
        },
      );

      if (res.data?['success'] == true) return null;

      // Validation errors carry the useful text in details[].
      final err = res.data?['error'];
      final details = err?['details'];
      if (details is List && details.isNotEmpty) {
        return details.map((d) => d['message']).join('\n');
      }
      return err?['message'] ?? 'Could not submit application';
    } on DioException {
      return 'Network error. Try again.';
    }
  }
}
