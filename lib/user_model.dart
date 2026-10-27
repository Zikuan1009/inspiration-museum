/// 云端用户档案。`appId` 只来自 Supabase `profiles.app_id`，禁止本地生成。
class UserModel {
  const UserModel({
    required this.id,
    required this.username,
    required this.avatarUrl,
    required this.bio,
    required this.followersCount,
    required this.followingCount,
    this.appId,
    this.age,
    this.gender = '',
    this.location = '',
    this.school = '',
    this.hobbies = '',
    this.personality = '',
    this.occupation = '',
    this.letterForms = const ['keyword', 'quote'],
    this.breakoutRatio = 30,
    this.observedNote = '',
  });

  final String id;
  final String username;
  final String avatarUrl;
  final String bio;
  final int followersCount;
  final int followingCount;
  final String? appId;
  final int? age;
  final String gender;
  final String location;
  final String school;
  final String hobbies;
  final String personality;
  final String occupation;

  /// 每日来信：keyword、quote 每天都在。其余是用户勾选的轮换内容。none 表示明确不选。
  final List<String> letterForms;

  /// 破圈比例，0 全是画像来信，100 全是领域馆藏。
  final int breakoutRatio;

  /// 从收藏、点赞和写下的感悟里看出的方向。不改写用户自己填的爱好。
  final String observedNote;

  String get displayAppId {
    final value = appId?.trim() ?? '';
    return value.isEmpty ? '--------' : value;
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? avatarUrl,
    String? bio,
    int? followersCount,
    int? followingCount,
    String? appId,
    int? age,
    bool clearAge = false,
    String? gender,
    String? location,
    String? school,
    String? hobbies,
    String? personality,
    String? occupation,
    List<String>? letterForms,
    int? breakoutRatio,
    String? observedNote,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      appId: appId ?? this.appId,
      age: clearAge ? null : (age ?? this.age),
      gender: gender ?? this.gender,
      location: location ?? this.location,
      school: school ?? this.school,
      hobbies: hobbies ?? this.hobbies,
      personality: personality ?? this.personality,
      occupation: occupation ?? this.occupation,
      letterForms: letterForms ?? this.letterForms,
      breakoutRatio: breakoutRatio ?? this.breakoutRatio,
      observedNote: observedNote ?? this.observedNote,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'avatar_url': avatarUrl,
        'bio': bio,
        'followers_count': followersCount,
        'following_count': followingCount,
        'app_id': appId,
        'age': age,
        'gender': gender,
        'location': location,
        'school': school,
        'hobbies': hobbies,
        'personality': personality,
        'occupation': occupation,
        'letter_forms': letterForms,
        'breakout_ratio': breakoutRatio,
        'observed_note': observedNote,
      };

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final username = json['username']?.toString().trim() ?? '';
    final ageRaw = json['age'];
    return UserModel(
      id: json['id']?.toString() ?? '',
      username: username.isEmpty ? 'ANON' : username,
      avatarUrl: json['avatar_url']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      followersCount: (json['followers_count'] as num?)?.toInt() ?? 0,
      followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
      // ignore: prefer_null_aware_operators
      appId: json['app_id'] != null ? json['app_id'].toString() : null,
      age: ageRaw is num ? ageRaw.toInt() : int.tryParse(ageRaw?.toString() ?? ''),
      gender: json['gender']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      school: json['school']?.toString() ?? '',
      hobbies: json['hobbies']?.toString() ?? '',
      personality: json['personality']?.toString() ?? '',
      occupation: json['occupation']?.toString() ?? '',
      letterForms: letterFormsFromJson(json['letter_forms']),
      breakoutRatio: breakoutRatioFromJson(json['breakout_ratio']),
      observedNote: json['observed_note']?.toString() ?? '',
    );
  }

  static const letterFormOrder = [
    'keyword',
    'quote',
    'image',
    'music',
    'city',
    'building',
    'film',
    'book',
    'none',
  ];

  static List<String> letterFormsFromJson(dynamic raw) {
    final picked = <String>[];
    if (raw is List) {
      for (final item in raw) {
        final value = item.toString();
        if (letterFormOrder.contains(value) && !picked.contains(value)) {
          picked.add(value);
        }
      }
    }
    if (picked.isEmpty) return const ['keyword', 'quote'];
    return [
      for (final form in letterFormOrder)
        if (picked.contains(form)) form,
    ];
  }

  static int breakoutRatioFromJson(dynamic raw) {
    final value = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    return (value ?? 30).clamp(0, 100);
  }

  factory UserModel.fromSupabase(Map<String, dynamic> json) {
    return UserModel.fromJson(json);
  }
}
