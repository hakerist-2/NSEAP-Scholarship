library;

/// Education catalog models — previously re-exported from `shared_ui`.
///
/// Kept in `lib/models` so `lib/repositories/education_repository.dart` and
/// all `*ApplicationPage` widgets can import without an external package.

/// A catalog school or a custom school name.
class School {
  const School({required this.id, required this.name});

  /// Null when the applicant typed a school outside the catalog.
  final String? id;
  final String name;

  factory School.fromJson(Map<String, dynamic> json) {
    return School(
      id: (json['id'] ?? json['school_id'])?.toString(),
      name: (json['name'] ?? json['school_name'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  /// Helper for `CatalogAutocompleteField.messageOption` — renders suggestion.
  static String message(School s) => s.name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is School && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'School(id: $id, name: $name)';
}

/// A catalog program/course or a custom program name.
class Program {
  const Program({required this.id, required this.name});

  /// Null when the applicant typed a program outside the catalog.
  final String? id;
  final String name;

  factory Program.fromJson(Map<String, dynamic> json) {
    return Program(
      id: (json['id'] ?? json['program_id'])?.toString(),
      name: (json['name'] ?? json['program_name'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  /// Helper for `CatalogAutocompleteField.messageOption`.
  static String message(Program p) => p.name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Program && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'Program(id: $id, name: $name)';
}

/// Saved education selection for the signed-in applicant.
class ApplicantEducation {
  const ApplicantEducation({this.school, this.program});

  final School? school;
  final Program? program;

  /// `applicant_education` row shape: `school_id`, `school_name`, `program_id`, `program_name`.
  factory ApplicantEducation.fromJson(Map<String, dynamic> json) {
    School? school;
    final schoolName = json['school_name']?.toString();
    final schoolId = json['school_id']?.toString();
    if (schoolName != null && schoolName.isNotEmpty) {
      school = School(id: schoolId, name: schoolName);
    } else if (schoolId != null && schoolId.isNotEmpty) {
      school = School(id: schoolId, name: schoolId);
    }

    Program? program;
    final programName = json['program_name']?.toString();
    final programId = json['program_id']?.toString();
    if (programName != null && programName.isNotEmpty) {
      program = Program(id: programId, name: programName);
    } else if (programId != null && programId.isNotEmpty) {
      program = Program(id: programId, name: programId);
    }

    return ApplicantEducation(school: school, program: program);
  }

  Map<String, dynamic> toJson() => {
    'school_id': school?.id,
    'school_name': school?.name,
    'program_id': program?.id,
    'program_name': program?.name,
  };
}

/// Requirement entry shown in `RequirementsFormWidget`.
///
/// Mirrors the former `shared_ui` `StudentDocument` used by both
/// `ApplicationPage` (applicant) and `ScholarApplicationPage`.
class StudentDocument {
  StudentDocument({
    required this.type,
    required this.title,
    required this.description,
    this.isSelected = false,
    this.fileName,
    this.bytes,
    this.mimeType,
    this.storagePath,
  });

  final String type;
  final String title;
  final String description;
  bool isSelected;
  String? fileName;
  List<int>? bytes;
  String? mimeType;
  String? storagePath;
}
