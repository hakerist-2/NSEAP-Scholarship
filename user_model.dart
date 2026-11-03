/// Application profile data associated with a Supabase auth user.
class UserModel {
  final String userId;
  final String? fullName;
  final String email;
  final String? contactNumber;
  final bool emailVerified;
  final String accountStatus;
  final String role;
  final String registrationType;
  final String? avatarPath;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserModel({
    required this.userId,
    this.fullName,
    required this.email,
    this.contactNumber,
    this.emailVerified = false,
    this.accountStatus = 'active',
    this.role = 'applicant',
    this.registrationType = 'new_applicant',
    this.avatarPath,
    this.createdAt,
    this.updatedAt,
  });

  /// Creates a profile from the snake_case `users` table representation.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['id'] as String,
      fullName: json['full_name'] as String?,
      email: json['email'] as String? ?? '',
      contactNumber: json['contact_number'] as String?,
      emailVerified: json['email_verified'] as bool? ?? false,
      accountStatus: json['account_status'] as String? ?? 'active',
      role: json['role'] as String? ?? 'applicant',
      registrationType: json['registration_type'] as String? ?? 'new_applicant',
      avatarPath: json['avatar_path'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  /// Converts this profile to the snake_case `users` table representation.
  Map<String, dynamic> toJson() {
    return {
      'id': userId,
      if (fullName != null) 'full_name': fullName,
      'email': email,
      if (contactNumber != null) 'contact_number': contactNumber,
      'email_verified': emailVerified,
      'account_status': accountStatus,
      'role': role,
      'registration_type': registrationType,
      if (avatarPath != null) 'avatar_path': avatarPath,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Returns a profile with the supplied non-null values replaced.
  UserModel copyWith({
    String? userId,
    String? fullName,
    String? email,
    String? contactNumber,
    bool? emailVerified,
    String? accountStatus,
    String? role,
    String? registrationType,
    String? avatarPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      contactNumber: contactNumber ?? this.contactNumber,
      emailVerified: emailVerified ?? this.emailVerified,
      accountStatus: accountStatus ?? this.accountStatus,
      role: role ?? this.role,
      registrationType: registrationType ?? this.registrationType,
      avatarPath: avatarPath ?? this.avatarPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}







