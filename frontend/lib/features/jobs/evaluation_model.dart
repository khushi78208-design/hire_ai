class Evaluation {
  final String applicationId;
  final int overallScore;
  final int skillScore;
  final int experienceScore;
  final int educationScore;
  final int projectScore;
  final String recommendation;
  final List<String> matchedSkills;
  final List<String> missingSkills;
  final List<String> strengths;
  final List<String> concerns;
  final String summary;
  final String locationNote;

  Evaluation({
    required this.applicationId,
    required this.overallScore,
    required this.skillScore,
    required this.experienceScore,
    required this.educationScore,
    required this.projectScore,
    required this.recommendation,
    required this.matchedSkills,
    required this.missingSkills,
    required this.strengths,
    required this.concerns,
    required this.summary,
    required this.locationNote,
  });

  static List<String> _list(dynamic v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? [];

  factory Evaluation.fromJson(Map<String, dynamic> j) => Evaluation(
    applicationId: j['application_id'] as String,
    overallScore: j['overall_score'] ?? 0,
    skillScore: j['skill_score'] ?? 0,
    experienceScore: j['experience_score'] ?? 0,
    educationScore: j['education_score'] ?? 0,
    projectScore: j['project_score'] ?? 0,
    recommendation: j['recommendation'] ?? 'review_required',
    matchedSkills: _list(j['matched_skills']),
    missingSkills: _list(j['missing_skills']),
    strengths: _list(j['strengths']),
    concerns: _list(j['concerns']),
    summary: j['summary'] ?? '',
    locationNote: j['location_note'] ?? '',
  );

  String get label {
    switch (recommendation) {
      case 'strong_match':
        return 'Strong match';
      case 'low_match':
        return 'Low match';
      default:
        return 'Review needed';
    }
  }
}
