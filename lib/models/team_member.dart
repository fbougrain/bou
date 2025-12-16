class TeamMember {
  final int id;
  final String name;
  final String role;
  final String? phone;
  final String? email;
  final String? country;
  final String? photoAsset; // optional local asset path for avatar
  final bool isOnline; // session-only presence flag

  TeamMember({
    required this.id,
    required this.name,
    required this.role,
    this.phone,
    this.email,
    this.country,
    this.photoAsset,
    this.isOnline = false,
  });

  factory TeamMember.fromMap(Map<String, dynamic> map) => TeamMember(
    id: map['id'] as int,
    name: map['name'] as String,
    role: map['role'] as String,
    phone: map['phone'] as String?,
    email: map['email'] as String?,
    country: map['country'] as String?,
    photoAsset: map['photoAsset'] as String?,
    isOnline: (map['isOnline'] as bool?) ?? false,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'role': role,
    if (phone != null) 'phone': phone,
    if (email != null) 'email': email,
    if (country != null) 'country': country,
    if (photoAsset != null) 'photoAsset': photoAsset,
    'isOnline': isOnline,
  };
}
