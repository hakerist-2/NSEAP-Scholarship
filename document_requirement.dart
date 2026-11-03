import 'education_catalog.dart';

/// An admin-managed upload requirement. The type stays stable as labels change.
class DocumentRequirement {
  const DocumentRequirement({
    required this.type,
    required this.title,
    required this.description,
    this.audience = 'applicant',
    this.sortOrder = 0,
  });

  final String type;
  final String title;
  final String description;
  final String audience;
  final int sortOrder;

  factory DocumentRequirement.fromJson(Map<String, dynamic> json) =>
      DocumentRequirement(
        type: json['document_type'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        audience: json['audience'] as String? ?? 'applicant',
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  static List<DocumentRequirement> fromSnapshot(List<dynamic> snapshot) =>
      snapshot
          .map(
            (row) => DocumentRequirement.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();

  /// Refresh definitions without losing files already selected for the same ID.
  static List<StudentDocument> mergeDocuments(
    List<DocumentRequirement> requirements,
    List<StudentDocument> previous,
  ) {
    final byType = {for (final document in previous) document.type: document};
    return requirements.map((requirement) {
      final old = byType[requirement.type];
      if (old != null &&
          old.title == requirement.title &&
          old.description == requirement.description) {
        return old;
      }
      return StudentDocument(
        type: requirement.type,
        title: requirement.title,
        description: requirement.description,
        isSelected: old?.isSelected ?? false,
        fileName: old?.fileName,
        bytes: old?.bytes,
        mimeType: old?.mimeType,
        storagePath: old?.storagePath,
      );
    }).toList();
  }
}
