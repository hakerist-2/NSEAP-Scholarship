import '../utils/document_requirements.dart';
import 'document_requirement.dart';

/// A submitted scholarship application with completion and interview status.
class ScholarshipApplicationRecord {
  const ScholarshipApplicationRecord({
    required this.id,
    required this.applicationNumber,
    required this.applicantType,
    required this.status,
    required this.submittedAt,
    required this.applicationDocumentsComplete,
    this.statusNote,
    this.interview,
  });

  final String id;
  final String applicationNumber;
  final String applicantType;
  final String status;
  final DateTime submittedAt;

  /// Whether all application-stage documents required for this applicant exist.
  final bool applicationDocumentsComplete;
  final String? statusNote;
  final InterviewScheduleRecord? interview;

  /// Whether the application has transitioned to scholar status.
  bool get isScholar => status == 'scholar';

  /// Whether this applicant type follows the interview workflow.
  bool get requiresInterview => applicantType == 'new_applicant';

  /// Creates an application from a row with document and interview joins.
  factory ScholarshipApplicationRecord.fromJson(Map<String, dynamic> json) {
    // Supabase may encode the one-to-one interview join as a map or list.
    final interviewJson = json['interview_schedules'];
    final InterviewScheduleRecord? interview;
    if (interviewJson is Map) {
      interview = InterviewScheduleRecord.fromJson(
        Map<String, dynamic>.from(interviewJson),
      );
    } else if (interviewJson is List && interviewJson.isNotEmpty) {
      interview = InterviewScheduleRecord.fromJson(
        Map<String, dynamic>.from(interviewJson.first as Map),
      );
    } else {
      interview = null;
    }

    // Completion is derived only from application-category document types.
    final documentsJson = json['scholarship_documents'];
    final documentTypes = documentsJson is List
        ? documentsJson
              .whereType<Map>()
              .where((document) => document['category'] == 'application')
              .map((document) => document['document_type'])
              .whereType<String>()
              .toSet()
        : <String>{};
    final applicantType = json['applicant_type'] as String? ?? 'new_applicant';
    final snapshot = json['requirements_snapshot'];
    final requiredDocumentTypes = snapshot is List
        ? DocumentRequirement.fromSnapshot(snapshot).map((r) => r.type).toSet()
        : DocumentRequirements.typesForApplicant(applicantType);

    return ScholarshipApplicationRecord(
      id: json['id'] as String,
      applicationNumber: json['application_number'] as String,
      applicantType: applicantType,
      status: json['status'] as String,
      submittedAt: DateTime.parse(json['submitted_at'] as String).toLocal(),
      applicationDocumentsComplete: documentTypes.containsAll(
        requiredDocumentTypes,
      ),
      statusNote: json['admin_remarks'] as String?,
      interview: interview,
    );
  }
}

/// The scheduled time and venue for an application's interview.
class InterviewScheduleRecord {
  const InterviewScheduleRecord({
    required this.scheduledAt,
    required this.location,
  });

  final DateTime scheduledAt;
  final String location;

  /// Creates an interview schedule from a joined schedule row.
  factory InterviewScheduleRecord.fromJson(Map<String, dynamic> json) {
    return InterviewScheduleRecord(
      scheduledAt: DateTime.parse(json['scheduled_at'] as String).toLocal(),
      location: json['location'] as String,
    );
  }
}

/// In-memory document content and metadata awaiting upload.
class ScholarshipDocumentUpload {
  const ScholarshipDocumentUpload({
    required this.type,
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  /// The canonical requirement identifier, not the display file name.
  final String type;
  final String fileName;
  final List<int> bytes;
  final String mimeType;
}
