import 'dart:typed_data';

/// Firestore-backed user profile for users/{uid}.
/// Avatar currently stored as raw bytes in memory only (future: Storage URL).
class UserProfile {
  final String name;
  final String title;
  final String country;
  final String phone;
  final String email;
  final List<String> roles; // e.g. ["member"], ["admin"].
  final int version; // schema version for future migrations.
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Uint8List? avatarBytes; // transient local image bytes
  final bool eulaAccepted; // Whether user has accepted EULA
  final DateTime? eulaAcceptedAt; // When EULA was accepted

  const UserProfile({
    required this.name,
    required this.title,
    this.country = '',
    this.phone = '',
    required this.email,
    required this.roles,
    required this.version,
    this.createdAt,
    this.updatedAt,
    this.avatarBytes,
    this.eulaAccepted = false,
    this.eulaAcceptedAt,
  });

  bool get isIncomplete =>
      name.trim().isEmpty || title.trim().isEmpty || email.trim().isEmpty;

  UserProfile copyWith({
    String? name,
    String? title,
    String? country,
    String? phone,
    String? email,
    List<String>? roles,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
    Uint8List? avatarBytes,
    bool clearAvatar = false,
    bool? eulaAccepted,
    DateTime? eulaAcceptedAt,
  }) {
    return UserProfile(
      name: name ?? this.name,
      title: title ?? this.title,
      country: country ?? this.country,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      roles: roles ?? this.roles,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      avatarBytes: clearAvatar ? null : (avatarBytes ?? this.avatarBytes),
      eulaAccepted: eulaAccepted ?? this.eulaAccepted,
      eulaAcceptedAt: eulaAcceptedAt ?? this.eulaAcceptedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'name': name,
        'title': title,
        'country': country,
        'phone': phone,
        'email': email,
        'roles': roles,
        'version': version,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'eulaAccepted': eulaAccepted,
        'eulaAcceptedAt': eulaAcceptedAt?.toIso8601String(),
        // avatarBytes intentionally excluded (use Storage later)
      };

  static UserProfile fromMap(Map<String, dynamic> data) => UserProfile(
        name: (data['name'] as String?) ?? '',
        title: (data['title'] as String?) ?? '',
        country: (data['country'] as String?) ?? '',
        phone: (data['phone'] as String?) ?? '',
        email: (data['email'] as String?) ?? '',
        roles: (data['roles'] is List)
            ? (data['roles'] as List).whereType<String>().toList()
            : const ['member'],
        version: (data['version'] as int?) ?? 1,
        createdAt: _parseDate(data['createdAt']),
        updatedAt: _parseDate(data['updatedAt']),
        eulaAccepted: (data['eulaAccepted'] as bool?) ?? false,
        eulaAcceptedAt: _parseDate(data['eulaAcceptedAt']),
      );

  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.tryParse(v);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static const UserProfile initial = UserProfile(
    name: '',
    title: '',
    country: '',
    phone: '',
    email: '',
    roles: ['member'],
    version: 1,
    eulaAccepted: false,
  );
}
